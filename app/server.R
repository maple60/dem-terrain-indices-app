server <- function(input, output, session) {
  # セッションごとに一時作業フォルダを分け、同時利用時のファイル上書きを防ぎます。
  work_dir <- tempfile("twi_shiny_")
  dir.create(work_dir, recursive = TRUE)
  session$onSessionEnded(function() {
    unlink(work_dir, recursive = TRUE, force = TRUE)
  })

  # DEMのパス、計算結果、ログメッセージをShinyの状態として保持します。
  dem_path <- shiny::reactiveVal(NULL)
  run_results <- shiny::reactiveVal(NULL)
  status_messages <- shiny::reactiveVal("DEMのアップロード待ちです。")

  # DEMを読み直したときに、古い結果プレビューとダウンロード選択肢を消します。
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

  # ログタブに表示するメッセージを時刻付きで追加します。
  append_status <- function(message) {
    status_messages(c(
      status_messages(),
      paste(format(Sys.time(), "%H:%M:%S"), message)
    ))
  }

  # DEMをterraで読めるか確認し、後続処理用のパスとして保存します。
  load_dem <- function(path, label) {
    dem <- terra::rast(path)
    validate_dem(dem, require_projected = FALSE)
    dem_path(path)
    reset_results()
    append_status(paste("DEMを読み込みました:", label))
  }

  # アップロードされたGeoTIFFを作業フォルダへコピーして読み込みます。
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

  # DEM入力方法の変更に応じて、サンプルDEMまたはアップロードDEMを読み込みます。
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

  # DEMが変わったらCRSを確認し、推奨EPSGを入力欄に反映します。
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

  # アップロードモードでは、ファイル選択直後にDEMを読み込み直します。
  shiny::observeEvent(input$dem_file, {
    if (!identical(input$dem_source, "upload")) {
      return(invisible(NULL))
    }
    load_uploaded_dem()
  })

  # 入力DEMをbase R/terraの静的プロットとして描画します。
  output$dem_plot <- shiny::renderPlot({
    shiny::req(dem_path())
    dem <- terra::rast(dem_path())
    terra::plot(dem, col = viridis_colors(), axes = FALSE, main = "DEM")
  })

  # Leaflet表示を選んだときだけ地図用の出力枠を作ります。
  output$dem_map_ui <- shiny::renderUI({
    shiny::req(dem_path())
    leaflet::leafletOutput("dem_map", height = 420)
  })

  # 入力DEMをLeafletのレイヤー付き地図として表示します。
  output$dem_map <- leaflet::renderLeaflet({
    shiny::req(dem_path())
    dem <- terra::rast(dem_path())
    leaflet_dem_map(dem)
  })

  # 入力DEMの行数、範囲、解像度、CRSなどの基本情報を表示します。
  output$dem_info <- shiny::renderTable(
    {
      shiny::req(dem_path())
      dem_metadata(terra::rast(dem_path()))
    },
    striped = TRUE,
    bordered = TRUE,
    spacing = "s"
  )

  # CRS確認タブに、入力DEMの座標系と中心座標を表示します。
  output$crs_info <- shiny::renderTable(
    {
      shiny::req(dem_path())
      crs_detail_table(terra::rast(dem_path()))
    },
    striped = TRUE,
    bordered = TRUE,
    spacing = "s"
  )

  # 地理座標系DEMの場合、JGD2011平面直角座標系とUTMの候補を表示します。
  output$crs_candidates <- shiny::renderTable(
    {
      shiny::req(dem_path())
      crs_recommendations(terra::rast(dem_path()))
    },
    striped = TRUE,
    bordered = TRUE,
    spacing = "s"
  )

  # ユーザーが手元で候補を確認できるよう、JGD2011の区域表を表示します。
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

  # 実行ボタンが押されたら、入力値を検証してTWI/TPI計算を開始します。
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
        # Shinyの進捗バーとログを同時に更新しながら、共有ワークフローを実行します。
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
        download_choices <- download_result_choices(result)
        shiny::updateCheckboxGroupInput(
          session,
          "download_algorithms",
          choices = download_choices,
          selected = unname(download_choices)
        )
        append_status("TWI/TPI計算が完了しました。")
      },
      error = function(e) {
        # 計算途中のエラーはログと通知の両方でユーザーに知らせます。
        append_status(paste("TWI/TPI計算に失敗しました:", conditionMessage(e)))
        shiny::showNotification(
          conditionMessage(e),
          type = "error",
          duration = NULL
        )
      }
    )
  })

  # 結果プレビューで選ばれているTWIまたはTPIの表示情報をまとめます。
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

  # 複数アルゴリズムのTWIを同じ色スケールで比較できるよう、共通範囲を返します。
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

  # 選択中のTWI/TPIラスターを静的プロットとして描画します。
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

  # Leaflet結果表示を選んだときだけ地図用の出力枠を作ります。
  output$twi_map_ui <- shiny::renderUI({
    selected_result()
    leaflet::leafletOutput("twi_map", height = 420)
  })

  # 選択中のTWI/TPIを、必要に応じて解析DEM由来の陰影起伏と重ねて表示します。
  output$twi_map <- leaflet::renderLeaflet({
    result <- selected_result()
    workflow_result <- run_results()
    shiny::req(workflow_result)
    selected_raster <- terra::rast(result$path)
    hillshade_source <- NULL
    if (
      !is.null(workflow_result$analysis_dem) &&
        file.exists(workflow_result$analysis_dem)
    ) {
      hillshade_source <- terra::rast(workflow_result$analysis_dem)
    }
    leaflet_raster_map(
      selected_raster,
      title = result$label,
      colors = result$colors,
      value_range = result$value_range,
      hillshade_source = hillshade_source
    )
  })

  # 計算結果の最小値、四分位数、最大値、NA割合を表にします。
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

  # ログメッセージを改行区切りのテキストとして表示します。
  output$status <- shiny::renderText({
    paste(status_messages(), collapse = "\n")
  })

  # 選択されたTWI/TPI結果とメタデータをZIPにまとめてダウンロードします。
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

      selections <- input$download_algorithms
      if (is.null(selections) || length(selections) == 0) {
        shiny::showNotification(
          "保存する結果を1つ以上選んでください。",
          type = "error"
        )
        stop("保存する結果を1つ以上選んでください。", call. = FALSE)
      }

      create_twi_results_zip(result, selections, file)
    },
    contentType = "application/zip"
  )
}
