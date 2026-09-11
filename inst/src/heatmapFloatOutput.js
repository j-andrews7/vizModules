// InteractiveComplexHeatmap's compact/float mode (output_ui_float = TRUE) does
// two things to the click/brush info panel. Its UI emits an inline script that
// detaches #<id>_output_wrapper and appends it to <body>, so the panel can be
// positioned from page coordinates without an ancestor's `position` or
// `overflow` getting in the way. Then template/ht-output.js parks it off-screen
// at `right: -10000px` -- on load, and again on every mouseleave, along with
// resetting its contents to "Retrieving from server... Don't move mouse.".
//
// An absolutely positioned box 10,000px past the right edge of the initial
// containing block extends the *document's* scrollable overflow, so the host
// page grows a ~10,400px horizontal scrollbar. Since the panel now lives on
// <body>, that applies to every page of the app, not just the one holding the
// heatmap, and scrolling right reveals the parked card sitting there for good.
//
// Browsers only extend the scroll region in the inline-end/block-end direction,
// so parking at `left: -10000px` hides the panel exactly as well and
// contributes no overflow at all. The package positions it with `left`/`top`
// (and `right: auto`) whenever it actually shows it, so only the parked state
// is rewritten and the floating behaviour is otherwise untouched.
(function ($) {
    // A real position is never anywhere near this far out; the park is -10000.
    var PARKED_RIGHT = -1000;

    function repark($wrapper) {
        // A shown panel has `right: auto`, which parses to NaN, so it is left
        // alone by the comparison below.
        if (parseFloat($wrapper.css("right")) < PARKED_RIGHT) {
            $wrapper.css({ right: "auto", left: -10000 });
        }
    }

    window.VizModules = window.VizModules || {};

    window.VizModules.heatmapFloatOutput = function (cfg) {
        if (!$) {
            return;
        }
        $(function () {
            var $wrapper = $("#" + cfg.id + "_output_wrapper");
            if (!$wrapper.length) {
                return;
            }

            repark($wrapper);

            // Bound after the package's own mouseleave handler: ht-output.js
            // arrives as a <head> dependency, so its ready callback is queued
            // ahead of this one, and jQuery fires handlers in binding order.
            $wrapper.on("mouseleave", function () {
                repark($wrapper);
            });
        });
    };
})(window.jQuery);
