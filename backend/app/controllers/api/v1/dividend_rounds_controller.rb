# frozen_string_literal: true

class Api::V1::DividendRoundsController < Api::V1::BaseController
  before_action :authenticate_user!
  before_action :set_company
  before_action :authorize_company_access!
  before_action :set_dividend_round, only: [:show]

  def index
    @dividend_rounds = @company.dividend_rounds.includes(:dividends)
    
    # Apply filters
    @dividend_rounds = @dividend_rounds.where(status: params[:status]) if params[:status].present?
    @dividend_rounds = @dividend_rounds.where(ready_for_payment: params[:ready_for_payment]) if params[:ready_for_payment].present?
    
    # Order by most recent first
    @dividend_rounds = @dividend_rounds.order(issued_at: :desc)
    
    # Pagination
    page = params[:page]&.to_i || 1
    per_page = [params[:per_page]&.to_i || 25, 100].min
    offset = (page - 1) * per_page
    
    total_count = @dividend_rounds.count
    @dividend_rounds = @dividend_rounds.limit(per_page).offset(offset)
    
    render json: {
      dividend_rounds: @dividend_rounds.map { |round| dividend_round_json(round) },
      pagination: {
        current_page: page,
        per_page: per_page,
        total_pages: (total_count / per_page.to_f).ceil,
        total_count: total_count
      }
    }
  end

  def show
    render json: { dividend_round: dividend_round_json(@dividend_round, include_dividends: true) }
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
    @dividend_round = @company.dividend_rounds.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Dividend round not found" }, status: :not_found
  end

  def dividend_round_json(dividend_round, include_dividends: false)
    result = {
      id: dividend_round.id,
      external_id: dividend_round.external_id,
      issued_at: dividend_round.issued_at,
      number_of_shares: dividend_round.number_of_shares,
      number_of_shareholders: dividend_round.number_of_shareholders,
      total_amount_cents: dividend_round.total_amount_in_cents,
      status: dividend_round.status,
      ready_for_payment: dividend_round.ready_for_payment,
      created_at: dividend_round.created_at,
      updated_at: dividend_round.updated_at,
      dividends_count: dividend_round.dividends.count
    }

    if include_dividends
      result[:dividends] = dividend_round.dividends.includes(:company_investor).map do |dividend|
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
          company_investor: {
            id: dividend.company_investor.id,
            external_id: dividend.company_investor.external_id,
            total_shares: dividend.company_investor.total_shares,
            investment_amount_cents: dividend.company_investor.investment_amount_in_cents
          }
        }
      end
    end

    result
  end
end