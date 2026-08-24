class CampaignsController < ApplicationController
  before_action :set_campaign, only: [:show, :edit, :update, :destroy, :dispatch]

  def index
    @campaigns = Campaign.with_stats.recent.page(params[:page])
  end

  def show
    @task_stats = @campaign.crawl_tasks.group(:status).count
    @tasks = @campaign.crawl_tasks.with_results.recent.page(params[:page])
  end

  def new
    @campaign = Campaign.new
  end

  def create
    @campaign = Campaign.new(campaign_params)

    if @campaign.save
      create_tasks_from_urls(@campaign, params[:urls])
      redirect_to @campaign, notice: "Kampanye berhasil dibuat!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @campaign.update(campaign_params)
      redirect_to @campaign, notice: "Kampanye berhasil diperbarui!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @campaign.destroy
    redirect_to campaigns_path, notice: "Kampanye dihapus."
  end

  def dispatch
    if @campaign.status == "active" && @campaign.dispatched_at.present?
      redirect_to @campaign, alert: "Tasks sudah di-dispatch sebelumnya."
      return
    end

    @campaign.update!(status: "active")
    TaskDispatcherJob.perform_later(@campaign.id)
    redirect_to @campaign, notice: "Tasks sedang dikirim ke antrean!"
  end

  private

  def set_campaign
    @campaign = Campaign.find(params[:id])
  end

  def campaign_params
    params.require(:campaign).permit(:name, :description, :status, :extraction_schema)
  end

  def create_tasks_from_urls(campaign, urls_text)
    return if urls_text.blank?

    urls = urls_text.to_s.split("\n").map(&:strip).reject(&:blank?)
    return if urls.empty?

    now = Time.current
    records = urls.map do |url|
      {
        campaign_id: campaign.id,
        target_url:  url,
        status:      "pending",
        created_at:  now,
        updated_at:  now
      }
    end

    CrawlTask.insert_all(records)
  end
end
