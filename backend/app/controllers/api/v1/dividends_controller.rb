# frozen_string_literal: true

class Api::V1::DividendsController < Api::V1::BaseController
  before_action :authenticate_user!
  before_action :set_company
  before_action :authorize_company_access!
  before_action :set_dividend_round, only: [:show]

  def index
    @dividends = @company.dividends.includes(:dividend_round, :company_investor)
    
    # Apply filters
    @dividends = @dividends.where(status: params[:status]) if params[:status].present?
    @dividends = @dividends.where(dividend_round_id: params[:dividend_round_id]) if params[:dividend_round_id].present?
    
    # Pagination
    page = params[:page]&.to_i || 1
    per_page = [params[:per_page]&.to_i || 25, 100].min
    offset = (page - 1) * per_page
    
    total_count = @dividends.count
    @dividends = @dividends.limit(per_page).offset(offset)
    
    render json: {
      dividends: @dividends.map { |dividend| dividend_json(dividend) },
      pagination: {
        current_page: page,
        per_page: per_page,
        total_pages: (total_count / per_page.to_f).ceil,
        total_count: total_count
      }
    }
  end

  def show
    @dividend = @company.dividends.find(params[:id])
    render json: { dividend: dividend_json(@dividend) }
  end

  private

  def authenticate_user!
    return if Current.user.present?
    render json: { error: "Unauthorized" }, status: :unauthorized
  end

  def set_company
    @company = Company.find(params[:company_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Company not found" }, status: :not_found
  end

  def authorize_company_access!
    # Check if user is company administrator or investor
    unless @company.company_administrators.exists?(user: Current.user) || 
           @company.company_investors.exists?(user: Current.user)
      render json: { error: "Forbidden" }, status: :forbidden
    end
  end

  def set_dividend_round
    @dividend_round = @company.dividend_rounds.find(params[:dividend_round_id]) if params[:dividend_round_id]
  end

  def dividend_json(dividend)
    {
      id: dividend.id,
      status: dividend.status,
      external_status: dividend.external_status,
      total_amount_cents: dividend.total_amount_in_cents,
      qualified_amount_cents: dividend.qualified_amount_cents,
      number_of_shares: dividend.number_of_shares,
      withheld_tax_cents: dividend.withheld_tax_cents,
      withholding_percentage: dividend.withholding_percentage,
      net_amount_cents: dividend.net_amount_in_cents,
      retained_reason: dividend.retained_reason,
      paid_at: dividend.paid_at,
      signed_release_at: dividend.signed_release_at,
      created_at: dividend.created_at,
      updated_at: dividend.updated_at,
      dividend_round: {
        id: dividend.dividend_round.id,
        external_id: dividend.dividend_round.external_id,
        issued_at: dividend.dividend_round.issued_at,
        status: dividend.dividend_round.status
      },
      company_investor: {
        id: dividend.company_investor.id,
        external_id: dividend.company_investor.external_id,
        total_shares: dividend.company_investor.total_shares,
        investment_amount_cents: dividend.company_investor.investment_amount_in_cents
      }
    }
  end
end