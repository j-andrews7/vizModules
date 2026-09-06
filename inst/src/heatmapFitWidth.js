// InteractiveComplexHeatmap sizes its panels in fixed pixels (450px for the
// original heatmap, 400px for the sub-heatmap) baked into the plotOutput div at
// UI construction time. The server's first renderPlot() call passes no
// width/height, so it takes whatever the div measures at bind time -- which is
// the fixed value, regardless of how much room the surrounding app actually
// has. The result is a heatmap that under-fills a wide monitor and overflows a
// laptop, and only snaps to the container once the jQuery UI resize handle is
// dragged.
//
// heatmapFitWidth() runs on DOM ready, before the server has had a chance to
// register the heatmap (makeInteractiveComplexHeatmap() needs a client round
// trip first), and rescales the panel widths to the space actually available.
// The first image the server draws is then already the right width.
(function ($) {
    // The plotOutput sits inside a wrapper div that is 4px wider/taller than
    // it; ht-main.js hard-codes the same offset everywhere it resizes.
    var RESIZE_PAD = 4;
    var MIN_PANEL_WIDTH = 200;
    // Below this the rescale is not worth a reflow (and risks fighting a
    // container whose own width is still settling).
    var MIN_SCALE_DELTA = 0.02;

    function scalePanel(id, panel, scale) {
        var $plot = $("#" + id + "_" + panel);
        if (!$plot.length) {
            return false;
        }

        var width = Math.max(MIN_PANEL_WIDTH, Math.round($plot.width() * scale));
        var alreadyDrawn = $plot.find("img").length > 0;

        $plot.width(width);
        $plot.find("img").width(width);
        $("#" + id + "_" + panel + "_resize").width(width + RESIZE_PAD);
        $("#" + id + "_" + panel + "_control").width(width);

        // Keep the widget's own size/download tabs showing the truth, exactly
        // as ht-main.js does after a drag.
        $("#" + id + "_" + panel + "_input_width").val(width);
        $("#" + id + "_" + panel + "_download_image_width").val(width);

        return alreadyDrawn;
    }

    function fitWidth(cfg) {
        var $root = $(cfg.root);
        if (!$root.length) {
            return;
        }

        var root = $root[0];
        var container = root.parentNode;
        var available = container ? container.clientWidth : 0;
        var natural = root.scrollWidth;
        if (!available || !natural) {
            return;
        }

        var scale = available / natural;
        if (Math.abs(scale - 1) < MIN_SCALE_DELTA) {
            return;
        }

        var mainRedrawn = false;
        $.each(cfg.panels, function (i, panel) {
            var alreadyDrawn = scalePanel(cfg.id, panel, scale);
            if (panel === "heatmap" && alreadyDrawn) {
                mainRedrawn = true;
            }
        });

        if (cfg.output) {
            var $output = $("#" + cfg.id + "_output_wrapper");
            if ($output.length) {
                $output.width(Math.round($output.width() * scale));
            }
        }

        // Shiny only recomputes an output's clientData size on window resize,
        // so the server would otherwise still see the old pixel width.
        $(window).trigger("resize");

        if (mainRedrawn && typeof Shiny !== "undefined") {
            // The heatmap was already drawn (a re-created UI, say), so the
            // stretched image needs a real redraw. Go through
            // InteractiveComplexHeatmap's own resize protocol rather than
            // registering a message handler, which would clobber its handlers.
            var $main = $("#" + cfg.id + "_heatmap");
            Shiny.setInputValue(cfg.id + "_heatmap_resize_width", $main.width());
            Shiny.setInputValue(cfg.id + "_heatmap_resize_height", $main.height());
            Shiny.setInputValue(cfg.id + "_heatmap_do_resize", Math.random());
        }
    }

    window.VizModules = window.VizModules || {};

    // Deferred to DOM ready so the widget's own inline scripts (which set the
    // wrapper sizes) and ht-main.js (which sets up .resizable()) have run.
    // Dependency scripts land in <head>, so their ready callbacks are queued
    // ahead of the call this registers from the document body.
    window.VizModules.heatmapFitWidth = function (cfg) {
        if (!$) {
            return;
        }
        $(function () {
            fitWidth(cfg);
        });
    };
})(window.jQuery);
