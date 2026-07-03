# DEM Terrain Indices App

DEM GeoTIFFから地形湿潤指数（TWI: Topographic Wetness Index）と地形位置指数（TPI: Topographic Position Index）を計算するShinyアプリです。入力DEMの確認、必要に応じた投影変換、複数の流量蓄積アルゴリズムによるTWI計算、セル近傍によるTPI計算、結果のプレビューとダウンロードをブラウザ上で行えます。

## 主な機能

- GeoTIFF形式のDEMアップロード、またはWhiteboxToolsのサンプルDEMの利用
- 入力DEMのメタデータ、CRS、解像度、範囲の確認
- 緯度経度DEMに対する投影変換候補の表示
- JGD2011平面直角座標系とUTMの候補EPSGコード表示
- D8、D-infinity、FD8による流量蓄積とTWI計算
- セル近傍サイズを指定したTPI計算
- DEM、TWI、TPIの静的プロットおよびLeaflet地図プレビュー
- 選択中の結果GeoTIFF単体、または計算条件・統計量・中間ファイルを含むZIPのダウンロード

## 構成

```text
app/
  app.R        # Shinyアプリのエントリーポイント
  global.R     # 共有関数、地形指標計算、WhiteboxTools初期化
  ui.R         # UI定義
  server.R     # Shinyサーバーロジック
  manifest.json
renv.lock      # Rパッケージの固定
```

## 必要なもの

- R 4.5.3相当
- `renv`
- Rパッケージ: `shiny`, `terra`, `whitebox`, `leaflet`
- WhiteboxTools実行ファイル

このリポジトリでは`.Rprofile`から`renv`を有効化します。初回は次を実行して、`renv.lock`に基づくパッケージ環境を復元してください。

```r
renv::restore()
```

WhiteboxTools実行ファイルが未設定の場合は、ローカル環境で一度インストールします。

```r
whitebox::install_whitebox()
```

必要に応じて`R_WHITEBOX_EXE_PATH`または`WHITEBOXTOOLS_DIR`でWhiteboxToolsの場所を指定できます。

## ローカル実行

リポジトリルートで次を実行します。

```r
shiny::runApp("app")
```

またはRStudioで`app/app.R`を開き、Run Appを実行します。

## 入力DEMの条件

- `.tif`または`.tiff`形式の単一レイヤGeoTIFF
- CRSが定義されていること
- TWI/TPI計算時は投影座標系であること

入力DEMが緯度経度座標系の場合、アプリの「CRS確認」タブで候補EPSGを確認し、「TWI/TPI計算前に投影変換する」を有効にしてから計算できます。

## 計算の流れ

1. DEMを読み込み、CRSとラスタ情報を確認します。
2. 必要に応じて指定EPSGへ投影変換します。
3. WhiteboxToolsで凹地処理を行います。
4. 勾配ラスタを作成します。
5. 選択したアルゴリズムで流量蓄積を計算します。
6. 流量蓄積と勾配からTWIを計算します。
7. 解析用DEMから、指定したセル近傍の平均標高との差としてTPIを計算します。

## 出力

結果タブでは、チェックしたTWI/TPI結果をZIPとして保存できます。ZIPには、選択内容に応じて以下が含まれます。

- 投影変換後DEM（投影変換した場合）
- 凹地処理後DEM
- 勾配ラスタ
- チェックしたアルゴリズムの流量蓄積ラスタ
- チェックしたアルゴリズムのTWIラスタ
- チェックした場合はTPIラスタ
- 計算条件、TWI/TPI統計量、出力ファイル一覧のCSV

## デプロイ時の注意

Posit Connect Cloudなどで`R_CONFIG_ACTIVE=connect_cloud`または`QUARTO_PROFILE=connect_cloud`が設定されている場合、アプリ起動時にLinux向けWhiteboxToolsを一時ディレクトリへ自動セットアップします。通常のローカル実行では、事前にWhiteboxToolsをインストールしておく想定です。

## ライセンス

このリポジトリ内のコードは MIT License の下で公開しています。

本アプリケーションは `shiny`, `terra`, `whitebox` などの外部パッケージ・外部ソフトウェアに依存しています。
それぞれの依存関係については、各パッケージ・ソフトウェアのライセンスを参照してください。