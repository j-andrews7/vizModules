test_that(".strip_svg_prolog drops everything before the root element", {
    doc <- paste(
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "svg11.dtd">',
        "<!-- Created by cairo -->",
        '<svg width="10pt"><g/></svg>',
        sep = "\n"
    )
    expect_equal(.strip_svg_prolog(doc), '<svg width="10pt"><g/></svg>')

    # Already a bare fragment: unchanged.
    expect_equal(.strip_svg_prolog("<svg/>"), "<svg/>")

    expect_null(.strip_svg_prolog("no markup here"))
    expect_null(.strip_svg_prolog(""))
    expect_null(.strip_svg_prolog(NA_character_))
    expect_null(.strip_svg_prolog(NULL))
})

test_that(".svg_set_px_size restates the outer size without touching the viewBox", {
    svg <- "<svg width='225.00pt' height='150.00pt' viewBox='0 0 225.00 150.00'><g/></svg>"
    out <- .svg_set_px_size(svg, 300, 200)

    expect_true(grepl('width="300"', out, fixed = TRUE))
    expect_true(grepl('height="200"', out, fixed = TRUE))
    # The viewBox is what does the scaling, so it must survive intact.
    expect_true(grepl("viewBox='0 0 225.00 150.00'", out, fixed = TRUE))
    expect_false(grepl("225.00pt", out, fixed = TRUE))
    # Only the root element is rewritten.
    expect_true(grepl("<g/></svg>", out, fixed = TRUE))

    # Without a viewBox, width/height *are* the user units, so rewriting them
    # would rescale the drawing rather than restate its size.
    plain <- "<svg width='100' height='50'><g/></svg>"
    expect_equal(.svg_set_px_size(plain, 300, 200), plain)

    # An attribute that is missing gets added.
    bare <- "<svg viewBox='0 0 10 10'><g/></svg>"
    out2 <- .svg_set_px_size(bare, 30, 20)
    expect_true(grepl('width="30"', out2, fixed = TRUE))
    expect_true(grepl('height="20"', out2, fixed = TRUE))
})

test_that(".svg_namespace_ids rewrites definitions and references together", {
    svg <- paste0(
        "<svg><defs><clipPath id='cp1'><rect/></clipPath>",
        "<g id=\"glyph-0\"/></defs>",
        "<g clip-path='url(#cp1)'><use xlink:href=\"#glyph-0\"/></g></svg>"
    )
    out <- .svg_namespace_ids(svg, "panel1")

    expect_true(grepl("id='panel1-cp1'", out, fixed = TRUE))
    expect_true(grepl("url(#panel1-cp1)", out, fixed = TRUE))
    expect_true(grepl('id="panel1-glyph-0"', out, fixed = TRUE))
    expect_true(grepl('xlink:href="#panel1-glyph-0"', out, fixed = TRUE))
    # Nothing left pointing at the un-prefixed name.
    expect_false(grepl("url(#cp1)", out, fixed = TRUE))

    # No prefix, no change.
    expect_equal(.svg_namespace_ids(svg, NULL), svg)
    expect_equal(.svg_namespace_ids(svg, ""), svg)

    # Prefixes are sanitised into something id-safe.
    expect_true(grepl(
        "id='mod-hm-cp1'",
        .svg_namespace_ids(svg, "mod hm"), fixed = TRUE
    ))
})

test_that(".draw_to_svg renders a drawing at a pixel size with unique ids", {
    a <- .draw_to_svg(function() plot(1:10), 300, 200, id_prefix = "panelA")
    b <- .draw_to_svg(function() plot(1:10), 300, 200, id_prefix = "panelB")

    expect_true(startsWith(a, "<svg "))
    expect_true(grepl('width="300"', a, fixed = TRUE))
    expect_true(grepl('height="200"', a, fixed = TRUE))

    # Two panels drawing the same thing mint the same raw ids, which is exactly
    # the collision the prefixing exists to prevent.
    ids <- function(x) unlist(regmatches(x, gregexpr("id='[^']+", x)))
    expect_length(intersect(ids(a), ids(b)), 0L)

    # Every internal reference still resolves to a definition in its own panel.
    refs <- unlist(regmatches(a, gregexpr("url[(]#[^)]+[)]", a)))
    if (length(refs)) {
        targets <- sub("[)]$", "", sub("^url[(]#", "", refs))
        expect_true(all(targets %in% sub("^id='", "", ids(a))))
    }

    # A non-numeric size is refused outright rather than handed to a device.
    expect_null(.draw_to_svg(function() plot(1:3), NA, 200))
    expect_null(.draw_to_svg(function() plot(1:3), 300, "wide"))

    # A card dragged down to nothing opens a device but leaves no room to draw
    # in. The error surfaces to the caller (figureBuilderServer() turns it into
    # a warning and drops that panel) rather than being silently swallowed.
    expect_error(.draw_to_svg(function() plot(1:3), 0, 0), "margins")
})

test_that(".draw_to_svg leaves no device open when the drawing fails", {
    before <- length(grDevices::dev.list())
    expect_error(
        .draw_to_svg(function() stop("boom"), 300, 200),
        "boom"
    )
    expect_equal(length(grDevices::dev.list()), before)
})

test_that(".draw_to_svg draws on the canvas the panel was rendered at", {
    # A panel on the Figure Builder canvas is drawn by shiny::renderPlot(), which
    # works at res = 72 -- so its pixel box is that many points of canvas. The
    # exporter has to use the same figure, because ComplexHeatmap sizes legends,
    # row labels and titles in absolute points: on a smaller canvas they keep
    # their size and the heatmap body, the only flexible element, absorbs the
    # whole shortfall. Exporting at 96 squeezed a legend-heavy heatmap's cells
    # down to a fraction of a point.
    expect_equal(eval(formals(.draw_to_svg)$res), 72)
    expect_equal(
        eval(formals(.draw_to_svg)$res),
        eval(formals(shiny::renderPlot)$res)
    )

    svg <- .draw_to_svg(function() plot(1:3), 480, 380)
    # At 72dpi one user unit is one pixel, so the viewBox matches the panel box.
    # `.` does not cross newlines, so match the attribute rather than the doc.
    vb <- as.numeric(strsplit(gsub("viewBox='|'", "",
        regmatches(svg, regexpr("viewBox='[^']+'", svg))), " ")[[1]])
    expect_equal(vb[3:4], c(480, 380))
    expect_true(grepl('width="480"', svg, fixed = TRUE))
    expect_true(grepl('height="380"', svg, fixed = TRUE))

    # A smaller canvas really does move the furniture relative to the drawing,
    # which is the failure this default exists to prevent.
    small <- .draw_to_svg(function() plot(1:3), 480, 380, res = 96)
    expect_false(identical(small, svg))
})
