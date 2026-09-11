test_that("multiDynamicInput builds widget with template and initial elements", {
    spec <- list(
        column = list(type = "select", args = list(choices = c("pathway", "score"))),
        side = list(type = "select", args = list(choices = c("Left", "Right"))),
        label_side = list(type = "select", args = list(label = "Label Side", choices = c("Bottom", "Top"))),
        label_size = list(type = "numeric", args = list(label = "Label Size", value = 10, min = 1, step = 0.5))
    )

    # Partial elements (omitting label_side and label_size) should have missing fields
    # completed from row_spec in the initial payload
    elements <- list(
        row1 = list(column = "pathway", side = "Left")
    )

    widget <- multiDynamicInput("row_ann", label = "Row Annotations", row_spec = spec, elements = elements)
    expect_true(inherits(widget, "shiny.tag"))

    deps <- htmltools::findDependencies(widget)
    dep_names <- vapply(deps, `[[`, "", "name")
    expect_true("multi-dynamic-input" %in% dep_names)

    initial_json <- widget$attribs[["data-initial"]]
    initial <- jsonlite::fromJSON(initial_json, simplifyVector = FALSE)
    expect_length(initial, 1)

    fields <- initial[[1]]$fields
    field_keys <- vapply(fields, `[[`, "", "key")
    expect_equal(field_keys, c("column", "side", "label_side", "label_size"))

    # Verify defaulted values
    field_vals <- stats::setNames(lapply(fields, `[[`, "value"), field_keys)
    expect_equal(field_vals$column, "pathway")
    expect_equal(field_vals$side, "Left")
    expect_equal(field_vals$label_side, "Bottom")
    expect_equal(field_vals$label_size, 10)
})

test_that(".mdi_value_to_payload completes missing fields from row_spec", {
    spec <- list(
        model_type = list(type = "select", args = list(choices = c("lm", "glm"), selected = "lm")),
        formula = list(type = "text", args = list(value = "y ~ x")),
        width = list(type = "numeric", args = list(value = 2))
    )

    elements <- list(
        list(model_type = "glm")
    )

    payload <- .mdi_value_to_payload(elements, names(spec), spec)
    expect_length(payload, 1)

    fields <- payload[[1]]$fields
    field_map <- stats::setNames(lapply(fields, `[[`, "value"), vapply(fields, `[[`, "", "key"))
    expect_equal(field_map$model_type, "glm")
    expect_equal(field_map$formula, "y ~ x")
    expect_equal(field_map$width, 2)
})

test_that(".register_multi_dynamic_input_handler parses initial and client payload accurately", {
    handler <- shiny:::inputHandlers$get("VizModules.multiDynamicInput")
    expect_true(is.function(handler))

    payload <- list(
        `_prefix` = "row annotations",
        rows = list(
            list(fields = list(
                list(key = "column", value = "pathway"),
                list(key = "side", value = "Left"),
                list(key = "label_side", value = "Bottom"),
                list(key = "label_size", value = 10)
            ))
        )
    )

    res <- handler(payload)
    expect_true(is.list(res))
    expect_named(res, "row annotations1")
    expect_equal(res[["row annotations1"]]$column, "pathway")
    expect_equal(res[["row annotations1"]]$side, "Left")
    expect_equal(res[["row annotations1"]]$label_side, "Bottom")
    expect_equal(res[["row annotations1"]]$label_size, 10)

    # Empty payload returns empty named list
    empty_res <- handler(list(`_prefix` = "row", rows = list()))
    expect_equal(empty_res, stats::setNames(list(), character(0)))
})
