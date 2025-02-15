class ArticlesController < ApplicationController
  http_basic_authenticate_with name: "base", password: "connect"

  def new
    @articles = Article.all
  end

  def create
    # 入力されたURLを取得
    url = params[:url]

    # FaradayでLambda関数を呼び出す
    response = Faraday.post(ENV["LAMBDA_URL"]) do |req|
      req.headers["Content-Type"] = "application/json"
      req.body = { url: url }.to_json
    end

    data = JSON.parse(response.body, symbolize_names: true)

      # Lambdaから返されたエラーメッセージ
      if data[:error]
          flash[:alert] = data[:error]
          return redirect_to root_path
      end

    risk_score, summary = analyze_article(data[:content])

    # 保存
    Article.create(
        title: data[:title],
        datetime: data[:datetime],
        content: data[:content],
        risk_score: risk_score,
        summary: summary
      )

    redirect_to root_path
  end

  private

  def analyze_article(content)
    # APIをたたくアクション
    client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"]) # OpenAIクライアントを作成

    # OpenAI APIへのリクエスト文
    system_content = "あなたはニュース記事からリスクを分析し、記事を要約する専門家です。"
    user_content = <<~TEXT
        以下のニュース記事について被害範囲・被害程度・社会的影響・死傷者や被害金額の大きさを元に1から100のリスクスコアをつけ、簡潔な要約を作成してください。リスクが大きいほどリスクスコアが大きくなることとします。また、以下の形式で出力してください

        以下の形式で出力してください：
        {"リスクスコア":<1から100のリスクスコア>,"要約":<ニュース記事の要約>}

        マークダウンの記法は使用せず、上記のJSONフォーマットで直接出力してください。

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
            temperature: 0
        }
    )

    # レスポンスからリスクスコアと要約を抽出
    begin
      content = response.dig("choices", 0, "message", "content")  # OpenAIクライアントは自動でハッシュに変換してくれてるため、そのままdigメソッドが使える
      parsed_response = JSON.parse(content, symbolize_names: true) # contentの内容はjsonで指定してるからパースが必要

      # 必要な値を格納
      risk_score = parsed_response[:リスクスコア]
      summary = parsed_response[:要約]

      [ risk_score, summary ]

    # APIからのレスポンスに必要なキーが含まれていない場合のエラーハンドリング
    rescue JSON::ParserError => e
      Rails.logger.error "JSONパースエラー: #{e.message}"
      [ 0, "JSONパースエラー" ]
    end
  end
end
