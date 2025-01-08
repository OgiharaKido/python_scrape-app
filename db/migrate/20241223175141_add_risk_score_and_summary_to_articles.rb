class AddRiskScoreAndSummaryToArticles < ActiveRecord::Migration[8.0]
  def change
    add_column :articles, :risk_score, :integer
    add_column :articles, :summary, :text
  end
end
