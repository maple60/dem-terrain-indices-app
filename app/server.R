server <- function(input, output, session) {
  # Each session receives its own temporary workspace so simultaneous users do
  # not overwrite one another's uploaded DEM or output rasters.
  work_dir <- tempfile("twi_shiny_")
  dir.create(work_dir, recursive = TRUE)
  session$onSessionEnded(function() {
    unlink(work_dir, recursive = TRUE, force = TRUE)
  })

  dem_path <- shiny::reactiveVal(NULL)
  run_results <- shiny::reactiveVal(NULL)
  status_messages <- shiny::reactiveVal("DEMのアップロード待ちです。")

  reset_results <- function() {
    run_results(NULL)
    shiny::updateSelectInput(
      session,
      "result_algorithm",
      choices = character(0)
    )
    shiny::updateCheckboxGroupInput(
      session,
      "download_algorithms",
      choices = character(0)
    )
  }

  append_status <- function(message) {
    status_messages(c(
      status_messages(),
      paste(format(Sys.time(), "%H:%M:%S"), message)
    ))
  }

  load_dem <- function(path, label) {
    dem <- terra::rast(path)
    validate_dem(dem, require_projected = FALSE)
    dem_path(path)
    reset_results()
    append_status(paste("DEMを読み込みました:", label))
  }

  load_uploaded_dem <- function() {
    tryCatch(
      {
        check_packages("terra")
        path <- copy_uploaded_dem(input$dem_file, work_dir)
        load_dem(path, input$dem_file$name)
      },
      error = function(e) {
        dem_path(NULL)
        reset_results()
        append_status(paste("DEM読み込みに失敗しました:", conditionMessage(e)))
        shiny::showNotification(conditionMessage(e), type = "error")
      }
    )
  }

  shiny::observeEvent(input$dem_source, {
    if (identical(input$dem_source, "sample")) {
      tryCatch(
        {
          path <- copy_sample_dem(work_dir)
          load_dem(path, "WhiteboxサンプルDEM")
        },
        error = function(e) {
          dem_path(NULL)
          reset_results()
          append_status(
            paste("サンプルDEM読み込みに失敗しました:", conditionMessage(e))
          )
          shiny::showNotification(conditionMessage(e), type = "error")
        }
      )
      return(invisible(NULL))
    }

    if (!is.null(input$dem_file)) {
      load_uploaded_dem()
      return(invisible(NULL))
    }

    dem_path(NULL)
    reset_results()
    status_messages("DEMのアップロード待ちです。")
  }, ignoreInit = FALSE)

  shiny::observeEvent(dem_path(), {
    path <- dem_path()
    if (is.null(path)) {
      shiny::updateTextInput(session, "target_epsg", value = "")
      return(invisible(NULL))
    }

    dem <- terra::rast(path)
    shiny::updateTextInput(
      session,
      "target_epsg",
      value = default_target_epsg(dem)
    )
  }, ignoreNULL = FALSE)

  shiny::observeEvent(input$dem_file, {
    if (!identical(input$dem_source, "upload")) {
      return(invisible(NULL))
    }
    load_uploaded_dem()
  })

  output$dem_plot <- shiny::renderPlot({
    shiny::req(dem_path())
    dem <- terra::rast(dem_path())
    terra::plot(dem, col = viridis_colors(), axes = FALSE, main = "DEM")
  })

  output$dem_map_ui <- shiny::renderUI({
    shiny::req(dem_path())
    leaflet::leafletOutput("dem_map", height = 420)
  })

  output$dem_map <- leaflet::renderLeaflet({
    shiny::req(dem_path())
    dem <- terra::rast(dem_path())
    leaflet_dem_map(dem)
  })

  output$dem_info <- shiny::renderTable(
    {
      shiny::req(dem_path())
      dem_metadata(terra::rast(dem_path()))
    },
    striped = TRUE,
    bordered = TRUE,
    spacing = "s"
  )

  output$crs_info <- shiny::renderTable(
    {
      shiny::req(dem_path())
      crs_detail_table(terra::rast(dem_path()))
    },
    striped = TRUE,
    bordered = TRUE,
    spacing = "s"
  )

  output$crs_candidates <- shiny::renderTable(
    {
      shiny::req(dem_path())
      crs_recommendations(terra::rast(dem_path()))
    },
    striped = TRUE,
    bordered = TRUE,
    spacing = "s"
  )

  output$jgd2011_zones <- shiny::renderTable(
    {
      zones <- jgd2011_zone_table()
      zones$epsg <- paste0("EPSG:", zones$epsg)
      zones
    },
    striped = TRUE,
    bordered = TRUE,
    spacing = "s"
  )

  shiny::observeEvent(input$run, {
    shiny::req(dem_path())
    algorithms <- input$algorithms
    if (length(algorithms) == 0) {
      shiny::showNotification(
        "流量蓄積アルゴリズムを1つ以上選んでください。",
        type = "error"
      )
      return(invisible(NULL))
    }
    tpi_window <- tryCatch(
      tpi_window_cells(input$tpi_window_cells),
      error = function(e) {
        shiny::showNotification(conditionMessage(e), type = "error")
        NULL
      }
    )
    if (is.null(tpi_window)) {
      return(invisible(NULL))
    }

    output_dir <- file.path(
      work_dir,
      paste0("output_", format(Sys.time(), "%Y%m%d_%H%M%S"))
    )
    total_steps <- 3 + 2 * length(algorithms)
    if (isTRUE(input$project_dem)) {
      total_steps <- total_steps + 1
    }
    step <- 0

    append_status("TWI/TPI計算を開始しました。")
    tryCatch(
      {
        result <- shiny::withProgress(message = "地形指標計算中", value = 0, {
          progress <- function(detail) {
            step <<- step + 1
            shiny::incProgress(1 / total_steps, detail = detail)
            append_status(detail)
          }

          run_twi_workflow(
            dem_path = dem_path(),
            algorithms = algorithms,
            output_dir = output_dir,
            breach_dist = input$breach_dist,
            breach_fill = input$breach_fill,
            tpi_window = tpi_window,
            project_dem = isTRUE(input$project_dem),
            target_epsg = input$target_epsg,
            progress = progress
          )
        })

        run_results(result)
        choices <- result_preview_choices(result)
        shiny::updateSelectInput(
          session,
          "result_algorithm",
          choices = choices,
          selected = unname(choices[1])
        )
        algorithm_choices <- algorithm_select_choices(names(result$algorithms))
        shiny::updateCheckboxGroupInput(
          session,
          "download_algorithms",
          choices = algorithm_choices,
          selected = names(result$algorithms)
        )
        append_status("TWI/TPI計算が完了しました。")
      },
      error = function(e) {
        append_status(paste("TWI/TPI計算に失敗しました:", conditionMessage(e)))
        shiny::showNotification(
          conditionMessage(e),
          type = "error",
          duration = NULL
        )
      }
    )
  })

  selected_result <- shiny::reactive({
    result <- run_results()
    shiny::req(result)
    result_key <- input$result_algorithm
    if (
      is.null(result_key) ||
        !nzchar(result_key) ||
        !result_key %in% unname(result_preview_choices(result))
    ) {
      result_key <- unname(result_preview_choices(result)[1])
    }

    if (identical(result_key, "tpi")) {
      return(list(
        index = "TPI",
        label = paste0(
          "TPI ",
          result$tpi$window_cells,
          "x",
          result$tpi$window_cells,
          "セル"
        ),
        path = result$tpi$tpi,
        value_range = result$tpi_range,
        colors = tpi_colors()
      ))
    }

    method <- sub("^twi:", "", result_key)
    item <- result$algorithms[[method]]
    list(
      index = "TWI",
      label = paste("TWI", item$algorithm),
      path = item$twi,
      value_range = selected_twi_range(),
      colors = viridis_colors()
    )
  })

  selected_twi_range <- shiny::reactive({
    result <- run_results()
    shiny::req(result)

    if (!is.null(result$twi_range)) {
      return(result$twi_range)
    }

    raster_paths_value_range(
      vapply(result$algorithms, function(item) item$twi, character(1))
    )
  })

  output$twi_plot <- shiny::renderPlot({
    result <- selected_result()
    selected_raster <- terra::rast(result$path)
    terra::plot(
      selected_raster,
      col = result$colors,
      range = result$value_range,
      axes = FALSE,
      main = result$label
    )
  })

  output$twi_map_ui <- shiny::renderUI({
    selected_result()
    leaflet::leafletOutput("twi_map", height = 420)
  })

  output$twi_map <- leaflet::renderLeaflet({
    result <- selected_result()
    selected_raster <- terra::rast(result$path)
    leaflet_raster_map(
      selected_raster,
      title = result$label,
      colors = result$colors,
      value_range = result$value_range
    )
  })

  output$twi_stats <- shiny::renderTable(
    {
      result <- run_results()
      shiny::req(result)

      terrain_statistics_table(result)
    },
    striped = TRUE,
    bordered = TRUE,
    spacing = "s"
  )

  output$output_files <- shiny::renderTable(
    {
      result <- run_results()
      shiny::req(result)

      rows <- lapply(result$algorithms, function(item) {
        data.frame(
          index = "TWI",
          result = item$algorithm,
          flow_accumulation = normalizePath(
            item$accumulation,
            winslash = "/",
            mustWork = FALSE
          ),
          raster = normalizePath(item$twi, winslash = "/", mustWork = FALSE),
          stringsAsFactors = FALSE
        )
      })

      if (!is.null(result$tpi) && !is.null(result$tpi$tpi)) {
        rows[[length(rows) + 1]] <- data.frame(
          index = "TPI",
          result = paste0(
            result$tpi$window_cells,
            "x",
            result$tpi$window_cells,
            "セル"
          ),
          flow_accumulation = "",
          raster = normalizePath(result$tpi$tpi, winslash = "/", mustWork = FALSE),
          stringsAsFactors = FALSE
        )
      }

      table <- do.call(rbind, rows)
      rownames(table) <- NULL
      table
    },
    striped = TRUE,
    bordered = TRUE,
    spacing = "s"
  )

  output$status <- shiny::renderText({
    paste(status_messages(), collapse = "\n")
  })

  output$download_results <- shiny::downloadHandler(
    filename = function() {
      result <- run_results()
      shiny::req(result)

      paste0(
        "terrain_indices_",
        format(result$finished_at, "%Y%m%d_%H%M%S"),
        ".zip"
      )
    },
    content = function(file) {
      result <- run_results()
      shiny::req(result)

      methods <- input$download_algorithms
      if (is.null(methods) || length(methods) == 0) {
        shiny::showNotification(
          "保存する結果を1つ以上選んでください。",
          type = "error"
        )
        stop("保存する結果を1つ以上選んでください。", call. = FALSE)
      }

      create_twi_results_zip(result, methods, file)
    },
    contentType = "application/zip"
  )
}
