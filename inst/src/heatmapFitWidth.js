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
//
// A heatmap on a tab that is not the active one measures zero wide on load, so
// there is nothing to scale against yet. Rather than giving up (which left every
// heatmap outside the landing tab at its baked-in width until dragged), the fit
// is retried when the container is first laid out, then stops watching.
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
            return;
        }

        var width = Math.max(MIN_PANEL_WIDTH, Math.round($plot.width() * scale));

        $plot.width(width);
        $plot.find("img").width(width);
        $("#" + id + "_" + panel + "_resize").width(width + RESIZE_PAD);
        $("#" + id + "_" + panel + "_control").width(width);

        // Keep the widget's own size/download tabs showing the truth, exactly
        // as ht-main.js does after a drag.
        $("#" + id + "_" + panel + "_input_width").val(width);
        $("#" + id + "_" + panel + "_download_image_width").val(width);
    }

    // Run `fn` once the Shiny session can actually take an input value. The
    // socket is not necessarily open at DOM ready, and a setInputValue() made
    // before it opens is dropped on the floor.
    function whenShinyReady(fn) {
        if (typeof Shiny === "undefined") {
            return;
        }
        if (Shiny.shinyapp && Shiny.shinyapp.$socket) {
            fn();
        } else {
            $(document).one("shiny:connected", fn);
        }
    }

    // Tell the server the main panel's real size, through the same three inputs
    // ht-main.js sets when the resize handle is dragged. InteractiveComplexHeatmap
    // redraws on these, and so does any app that tracks the heatmap's geometry
    // server-side -- mapping a cursor back to a cell needs positions measured at
    // the size actually on screen, so a silent rescale would leave every later
    // hover reading against a layout that no longer exists.
    function notifyResize(cfg) {
        if ($.inArray("heatmap", cfg.panels) === -1) {
            return;
        }
        whenShinyReady(function () {
            var $main = $("#" + cfg.id + "_heatmap");
            if (!$main.length) {
                return;
            }
            Shiny.setInputValue(cfg.id + "_heatmap_resize_width", $main.width());
            Shiny.setInputValue(cfg.id + "_heatmap_resize_height", $main.height());
            Shiny.setInputValue(cfg.id + "_heatmap_do_resize", Math.random());
        });
    }

    // Returns true once the fit is settled (done, or close enough to leave
    // alone), false while the widget still has no measurable width.
    function fitWidth(cfg) {
        var $root = $(cfg.root);
        if (!$root.length) {
            return false;
        }

        var root = $root[0];
        var container = root.parentNode;
        var available = container ? container.clientWidth : 0;
        var natural = root.scrollWidth;
        // Not laid out yet -- an inactive tab, or a container still settling.
        if (!available || !natural) {
            return false;
        }

        var scale = available / natural;
        if (Math.abs(scale - 1) < MIN_SCALE_DELTA) {
            return true;
        }

        $.each(cfg.panels, function (i, panel) {
            scalePanel(cfg.id, panel, scale);
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
        notifyResize(cfg);

        return true;
    }

    // The widget measured zero wide, so it is not on screen yet. Watch its
    // container and fit as soon as it has a width -- opening the tab that holds
    // it, typically. One-shot: stop watching the moment the fit lands, so our
    // own width changes cannot retrigger it.
    function fitWhenVisible(cfg) {
        var $root = $(cfg.root);
        if (!$root.length || typeof ResizeObserver === "undefined") {
            return;
        }
        var container = $root[0].parentNode;
        if (!container) {
            return;
        }

        var observer = new ResizeObserver(function () {
            if (fitWidth(cfg)) {
                observer.disconnect();
            }
        });
        observer.observe(container);
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
            if (!fitWidth(cfg)) {
                fitWhenVisible(cfg);
            }
        });
    };
})(window.jQuery);
