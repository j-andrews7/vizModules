#' Strip everything before an SVG document's root element
#'
#' An SVG file starts with an XML prolog, usually a DOCTYPE, and (for the cairo
#' device) a comment banner. None of that may appear part-way through a larger
#' document, so it is dropped before the markup is spliced into one.
#'
#' @param svg A character scalar holding an SVG document.
#'
#' @return The markup from its `<svg` element onwards, or `NULL` if the input
#'   holds no root element.
#'
#' @author Jared Andrews
#' @rdname INTERNAL_strip_svg_prolog
#' @keywords internal
.strip_svg_prolog <- function(svg) {
    if (!is.character(svg) || length(svg) != 1L || is.na(svg) || !nzchar(svg)) {
        return(NULL)
    }
    pos <- regexpr("<svg", svg, fixed = TRUE)
    if (pos < 0L) {
        return(NULL)
    }
    substring(svg, pos)
}


#' Restate an SVG fragment's outer size in pixels
#'
#' Both SVG devices size the document in points while expressing its `viewBox`
#' in a matching set of user units. Splicing that into a pixel-sized figure
#' leaves the panel's on-page size at the mercy of whatever point-to-pixel ratio
#' the reader applies, so the root element's `width`/`height` are restated in
#' pixels here. The `viewBox` is left alone and does the scaling, exactly as it
#' does for the plotly panels (which are asked for a pixel size directly).
#'
#' @param svg A character scalar holding an SVG document or fragment.
#' @param width,height Size in pixels.
#'
#' @return `svg` with its root element resized, or unchanged if it carries no
#'   `viewBox` to scale against.
#'
#' @author Jared Andrews
#' @rdname INTERNAL_svg_set_px_size
#' @keywords internal
.svg_set_px_size <- function(svg, width, height) {
    if (!is.character(svg) || length(svg) != 1L) {
        return(svg)
    }
    m <- regexpr("<svg[^>]*>", svg)
    if (m < 0L) {
        return(svg)
    }
    tag <- regmatches(svg, m)
    # Without a viewBox the user units are whatever width/height say, so
    # rewriting them would rescale the drawing rather than restate its size.
    if (!grepl("viewBox", tag, fixed = TRUE)) {
        return(svg)
    }

    set_attr <- function(x, name, value) {
        pattern <- paste0("\\s", name, "\\s*=\\s*(['\"])[^'\"]*\\1")
        replacement <- paste0(" ", name, "=\"", value, "\"")
        if (grepl(pattern, x)) {
            sub(pattern, replacement, x)
        } else {
            sub("^<svg", paste0("<svg", replacement), x)
        }
    }

    tag <- set_attr(tag, "width", width)
    tag <- set_attr(tag, "height", height)
    regmatches(svg, m) <- tag
    svg
}


#' Namespace every id inside an SVG fragment
#'
#' Two SVG fragments dropped into one document share an id space. Both SVG
#' devices mint ids of their own -- clip paths for \pkg{svglite}, glyph symbols
#' for cairo -- and two panels drawn from similar data can easily mint the same
#' one, at which point a `url(#...)` or `href="#..."` reference resolves to
#' whichever came first and a panel is clipped or lettered with its neighbour's
#' definitions.
#'
#' A self-contained fragment only ever references ids it defines itself, so
#' prefixing the definition sites and the reference sites in one pass keeps
#' every reference pointing where it did while making the whole set unique to
#' the panel.
#'
#' @param svg A character scalar holding an SVG document or fragment.
#' @param prefix Character scalar prepended (with a separating `-`) to every id.
#'   `NULL` or `""` leaves `svg` untouched.
#'
#' @return `svg` with its ids namespaced.
#'
#' @author Jared Andrews
#' @rdname INTERNAL_svg_namespace_ids
#' @keywords internal
.svg_namespace_ids <- function(svg, prefix) {
    if (!is.character(svg) || length(svg) != 1L ||
        is.null(prefix) || !nzchar(prefix)) {
        return(svg)
    }
    pre <- paste0(gsub("[^A-Za-z0-9_-]+", "-", prefix), "-")

    # Definitions: id="x" / id='x'
    svg <- gsub("(\\sid=['\"])", paste0("\\1", pre), svg, perl = TRUE)
    # References: url(#x)
    svg <- gsub("(url\\(#)", paste0("\\1", pre), svg, perl = TRUE)
    # References: href="#x" / xlink:href='#x'
    svg <- gsub("((?:xlink:)?href=['\"]#)", paste0("\\1", pre), svg, perl = TRUE)
    svg
}


#' Render a grid or base drawing to a self-contained SVG fragment
#'
#' Draws onto an SVG device and returns the markup, ready to be placed inside a
#' larger SVG document. This is what lets a module whose output is not a plotly
#' graph still contribute vector art to the Figure Builder's figure export: see
#' the `vector_svg` attribute documented in [figureBuilderServer()].
#'
#' \pkg{svglite} is used when it is installed, because it writes real `<text>`
#' elements, so labels stay editable in a vector editor. The cairo device
#' ([grDevices::svg()]) is the fallback: still vector, but it converts text to
#' glyph paths, which cannot be edited or restyled afterwards.
#'
#' @param draw_fn A function of no arguments that draws onto the active device.
#' @param width,height Size in pixels.
#' @param res Pixels per inch used to convert `width`/`height` to the inches the
#'   SVG devices take. The default matches [shiny::renderPlot()]'s own `res`, so
#'   the fragment is drawn on a canvas the same physical size as the one the
#'   panel was rendered at on screen. That is not cosmetic: a `ComplexHeatmap`
#'   legend, its row labels and its titles are all sized in absolute points, so
#'   a canvas even slightly smaller than the on-screen one leaves them the same
#'   size while the heatmap body -- the one flexible element -- absorbs the
#'   entire shortfall. Exporting a legend-heavy heatmap 25% small squeezed its
#'   cells down to nothing.
#' @param id_prefix Optional character scalar used to namespace the fragment's
#'   ids, so several fragments can share one document. See
#'   [.svg_namespace_ids()].
#' @param bg Background color.
#'
#' @return A character scalar holding an `<svg>` element, or `NULL` if the
#'   requested size is not usable. An error raised by `draw_fn` itself (a panel
#'   dragged too small to leave any plotting room, say) propagates to the
#'   caller, which is better placed to decide whether to drop that panel or fail
#'   the whole export; the device is closed either way.
#'
#' @author Jared Andrews
#' @rdname INTERNAL_draw_to_svg
#' @keywords internal
.draw_to_svg <- function(draw_fn, width, height, res = 72,
                         id_prefix = NULL, bg = "white") {
    stopifnot(is.function(draw_fn))

    width <- suppressWarnings(as.numeric(width))
    height <- suppressWarnings(as.numeric(height))
    res <- suppressWarnings(as.numeric(res))
    if (anyNA(c(width, height, res)) || length(c(width, height, res)) != 3L ||
        res <= 0) {
        return(NULL)
    }
    # A card can be dragged down to a sliver; an SVG device given a zero or
    # negative size errors rather than drawing nothing.
    width <- max(width, 1)
    height <- max(height, 1)

    file <- tempfile(fileext = ".svg")
    dev_open <- FALSE
    on.exit(
        {
            if (dev_open) {
                try(grDevices::dev.off(), silent = TRUE)
            }
            unlink(file)
        },
        add = TRUE
    )

    if (requireNamespace("svglite", quietly = TRUE)) {
        svglite::svglite(file,
            width = width / res, height = height / res, bg = bg,
            standalone = FALSE
        )
    } else {
        grDevices::svg(file, width = width / res, height = height / res, bg = bg)
    }
    dev_open <- TRUE

    draw_fn()

    grDevices::dev.off()
    dev_open <- FALSE

    if (!file.exists(file)) {
        return(NULL)
    }

    out <- .strip_svg_prolog(paste(readLines(file, warn = FALSE), collapse = "\n"))
    if (is.null(out)) {
        return(NULL)
    }
    .svg_set_px_size(.svg_namespace_ids(out, id_prefix), width, height)
}
