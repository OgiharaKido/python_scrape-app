class ArticlesController < ApplicationController
    http_basic_authenticate_with name: "インターン", password: "ganbarimasu"
    require "selenium-webdriver"
    require "nokogiri"
    require "openai"


    def new
        @articles = Article.all
    end

    def create
        url = params[:url]
        scraped_data = scrape_article(url)

    if scraped_data
        # スクレイプしたデータとリスクスコア・要約を保存
        risk_score, summary = analyze_article(scraped_data[:content])

        @article = Article.create(scraped_data.merge(risk_score: risk_score, summary: summary))
        redirect_to root_path
    else
        flash[:alert] = "スクレイピングに失敗しました。"
        redirect_to root_path
    end
    end



    private

    def scrape_article(url)
        # スクレイプのためのアクション
        options = Selenium::WebDriver::Chrome::Options.new
        options.add_argument("--headless")
        driver = Selenium::WebDriver.for(:chrome, options: options)
        driver.get(url)

        sleep 2
        doc = Nokogiri::HTML(driver.page_source)
        driver.quit

        {
            title: doc.at_css("div.content--detail-title span").text || "タイトルが見つかりませんでした",
            datetime: doc.at_css("div.content--detail-title time").text || "日時が見つかりませんでした",
            content: doc.css("div.content--detail-body p, div.content--detail-more p").map(&:inner_html) || "本文が見つかりませんでした"
        }
    rescue => e
        puts "Error: #{e.message}"
        nil
    end

    def analyze_article(content)
        # APIをたたくアクション
        client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"]) # OpenAIクライアントを作成

        system_content = "あなたはニュース記事からリスクを分析し、記事を要約する専門家です。"

        user_content = <<~TEXT
            以下のニュース記事について被害範囲・被害程度・社会的影響・死傷者や被害金額の大きさを元に1から100のリスクスコアをつけ、簡潔な要約を作成してください。リスクが大きいほどリスクスコアが大きくなることとします。また、以下の形式で出力してください

            ```json
            {
                "リスクスコア":<1から100のリスクスコア>,
                "要約":<ニュース記事の要約>
            }
            ```

            必ずこの形式で回答し、それ以外の文言は含めないでください。

            本文: #{content}
            TEXT

        # リクエストのパラメータ
        response = client.chat(
            parameters: {
                model: "gpt-4o", # 使用するモデル
                messages: [
                    { role: "system", content: system_content },
                    { role: "user", content: user_content }
                ],
                max_tokens: 200,
                temperature: 0.3
                }
            )

        # レスポンスの解析
        if response["choices"]
        result_text = response.dig("choices", 0, "message", "content")

            if result_text =~ /```json\s*({.*?})\s*```/m # JSON部分を正規表現でキャプチャ
                json_text = $1  # JSON部分を抽出
            else
                # 正規表現マッチのエラーハンドリング
                raise "形式エラー: JSON形式が見つかりません。レスポンス: #{result_text}"
            end

        # JSON文字列をシンボルキーのハッシュ形式に変換
        parsed_response = JSON.parse(json_text, symbolize_names: true)

        # 必須キーの存在チェック
        if parsed_response.key?(:リスクスコア) && parsed_response.key?(:要約)
            risk_score = parsed_response[:リスクスコア]
            summary = parsed_response[:要約]
            [ risk_score, summary ]
        else
            # 必須キーが不足している場合のエラーハンドリング
            raise "JSON解析エラー: 必須キーが不足しています レスポンス: #{json_text}"
        end

        end
    end
end
