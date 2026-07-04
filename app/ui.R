# UIだけを定義するファイルです。
# 入力値への反応はserver.R、計算や地図表示の共通処理はglobal.Rに置きます。
ui <- shiny::fluidPage(
  # 画面全体の余白、背景、表・プロットの見た目をまとめて調整します。
  shiny::tags$head(
    shiny::tags$style(shiny::HTML(
      "
      body { background: #f7f7f5; }
      .container-fluid { max-width: 1320px; }
      .well { background: #ffffff; border-radius: 6px; }
      .plot-box { min-height: 360px; }
      pre { white-space: pre-wrap; }
    "
    ))
  ),

  shiny::titlePanel("TWI/TPI計算"),
  shiny::sidebarLayout(
    shiny::sidebarPanel(
      # DEMの入力方法を、アップロードとWhiteboxのサンプルDEMから選びます。
      shiny::radioButtons(
        "dem_source",
        "DEM入力",
        choices = c(
          "GeoTIFFをアップロード" = "upload",
          "サンプルDEMを使用" = "sample"
        ),
        selected = "upload"
      ),
      # アップロードを選んだ場合だけ、GeoTIFFの選択欄を表示します。
      shiny::conditionalPanel(
        "input.dem_source == 'upload'",
        shiny::fileInput(
          "dem_file",
          "DEM GeoTIFF",
          accept = c(".tif", ".tiff")
        )
      ),
      # TWI計算で使う流量蓄積アルゴリズムを複数選択できるようにします。
      shiny::checkboxGroupInput(
        "algorithms",
        "TWI流量蓄積アルゴリズム",
        choices = algorithm_choices,
        selected = c("d8", "dinf")
      ),
      # TPIは中心セルを除いた近傍平均との差で計算するため、奇数セル数を受け取ります。
      shiny::numericInput(
        "tpi_window_cells",
        "TPI近傍サイズ（セル、奇数）",
        value = 3,
        min = 3,
        step = 2
      ),
      # WhiteboxToolsのdepression breachingで使う探索距離とfill指定です。
      shiny::numericInput(
        "breach_dist",
        "Breach距離",
        value = 20,
        min = 1,
        step = 1
      ),
      shiny::checkboxInput(
        "breach_fill",
        "残った凹地をfillする",
        value = TRUE
      ),
      shiny::hr(),
      # 緯度経度DEMなどを使う場合、計算前に投影座標系へ変換する任意設定です。
      shiny::checkboxInput(
        "project_dem",
        "TWI/TPI計算前に投影変換する",
        value = FALSE
      ),
      shiny::textInput(
        "target_epsg",
        "変換先EPSG",
        value = "",
        placeholder = "例: 6677"
      ),
      shiny::actionButton(
        "run",
        "TWI/TPIを計算",
        class = "btn-primary"
      )
    ),
    shiny::mainPanel(
      shiny::tabsetPanel(
        # 入力DEMを静的プロットまたはLeaflet地図で確認します。
        shiny::tabPanel(
          "DEMプレビュー",
          shiny::br(),
          shiny::radioButtons(
            "dem_view_mode",
            "表示",
            choices = c(
              "静的プロット" = "plot",
              "インタラクティブ地図" = "map"
            ),
            selected = "plot",
            inline = TRUE
          ),
          shiny::conditionalPanel(
            "input.dem_view_mode == 'plot'",
            shiny::plotOutput("dem_plot", height = 420)
          ),
          shiny::conditionalPanel(
            "input.dem_view_mode == 'map'",
            shiny::uiOutput("dem_map_ui")
          ),
          shiny::tableOutput("dem_info")
        ),

        # CRS情報と、地理座標系DEM向けの投影候補を確認します。
        shiny::tabPanel(
          "CRS確認",
          shiny::br(),
          shiny::h4("入力DEM"),
          shiny::tableOutput("crs_info"),
          shiny::h4("投影候補"),
          shiny::tableOutput("crs_candidates"),
          shiny::h4("JGD2011平面直角座標系 早見表"),
          shiny::tableOutput("jgd2011_zones"),

          shiny::tags$p(
            shiny::tags$small(
              "出典：",
              shiny::tags$a(
                href = "https://www.gsi.go.jp/LAW/heimencho.html",
                target = "_blank",
                rel = "noopener noreferrer",
                "平面直角座標系（平成十四年国土交通省告示第九号） | 国土地理院"
              )
            )
          )
        ),

        # 計算後のTWI/TPI表示、統計、ダウンロード対象の選択をまとめます。
        shiny::tabPanel(
          "結果",
          shiny::br(),
          shiny::fluidRow(
            shiny::column(
              width = 8,
              shiny::radioButtons(
                "twi_view_mode",
                "表示",
                choices = c(
                  "静的プロット" = "plot",
                  "インタラクティブ地図" = "map"
                ),
                selected = "plot",
                inline = TRUE
              ),
              shiny::conditionalPanel(
                "input.twi_view_mode == 'plot'",
                shiny::plotOutput("twi_plot", height = 420)
              ),
              shiny::conditionalPanel(
                "input.twi_view_mode == 'map'",
                shiny::uiOutput("twi_map_ui")
              )
            ),
            shiny::column(
              width = 4,
              shiny::selectInput(
                "result_algorithm",
                "結果プレビュー",
                choices = character(0)
              ),
              shiny::checkboxGroupInput(
                "download_algorithms",
                "保存するTWI/TPI結果",
                choices = character(0)
              ),
              shiny::downloadButton(
                "download_results",
                "チェックした結果一式を保存"
              )
            )
          ),
          shiny::h4("結果統計"),
          shiny::tableOutput("twi_stats")
        ),

        # DEM読み込みや計算の進行状況を時刻付きで表示します。
        shiny::tabPanel(
          "ログ",
          shiny::br(),
          shiny::verbatimTextOutput("status")
        ),

        # リポジトリと関連ノートブックへの参照を置きます。
        shiny::tabPanel(
          "About",
          shiny::br(),
          shiny::tags$a(
            href = "https://github.com/maple60/dem-terrain-indices-app",
            target = "_blank",
            rel = "noopener noreferrer",
            shiny::icon("github"),
            " GitHub repository"
          ),
          shiny::br(),
          shiny::tags$p(
            "コードについて詳しく知りたい場合は、",
            shiny::tags$a(
              href = "https://maple60.github.io/dem-twi-r/",
              target = "_blank",
              rel = "noopener noreferrer",
              "こちらのノートブック"
            ),
            "を参照してください。"
          )
        )
      )
    )
  )
)
