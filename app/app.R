# アプリの小さな入口だけを置くファイルです。
# UI、サーバー処理、地形指標の計算処理は隣接ファイルに分けています。
app_dir <- if (file.exists("global.R")) "." else "app"

# 共有関数を先に読み込み、必要に応じてWhiteboxToolsを初期化します。
source(file.path(app_dir, "global.R"), local = TRUE, encoding = "UTF-8")
if (is_connect_cloud()) {
  initialize_whitebox(install_if_missing = TRUE)
}

# ShinyのUI定義とサーバー定義を読み込み、アプリとして起動します。
source(file.path(app_dir, "ui.R"), local = TRUE, encoding = "UTF-8")
source(file.path(app_dir, "server.R"), local = TRUE, encoding = "UTF-8")

shiny::shinyApp(ui = ui, server = server)
