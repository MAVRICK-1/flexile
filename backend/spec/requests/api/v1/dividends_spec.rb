# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "Api::V1::Dividends", type: :request do
  let(:company) { create(:company) }
  let(:user) { create(:user) }
  let(:administrator) { create(:company_administrator, company: company, user: user) }
  let(:investor) { create(:company_investor, company: company, user: user) }
  let(:dividend_round) { create(:dividend_round, company: company) }
  let(:dividend) { create(:dividend, company: company, dividend_round: dividend_round, company_investor: investor) }

  before do
    # Mock Clerk authentication
    allow_any_instance_of(Api::V1::DividendsController).to receive(:clerk).and_return(
      double(user?: true, user_id: user.clerk_id)
    )
    allow(User).to receive(:find_by).with(clerk_id: user.clerk_id).and_return(user)
    allow(Current).to receive(:user).and_return(user)
  end

  describe "GET /api/v1/companies/:company_id/dividends" do
    context "when user is authenticated and authorized" do
      before { administrator } # Create administrator association

      it "returns dividends for the company" do
        dividend # Create dividend
        get "/v1/companies/#{company.id}/dividends", headers: { "Host" => "flexile.dev" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        
        expect(json["dividends"]).to be_an(Array)
        expect(json["dividends"].length).to eq(1)
        expect(json["dividends"].first["id"]).to eq(dividend.id)
        expect(json["dividends"].first["status"]).to eq(dividend.status)
        expect(json["dividends"].first["total_amount_cents"]).to eq(dividend.total_amount_in_cents)
        expect(json["dividends"].first["dividend_round"]["id"]).to eq(dividend_round.id)
        expect(json["dividends"].first["company_investor"]["id"]).to eq(investor.id)
      end

      it "includes pagination metadata" do
        get "/v1/companies/#{company.id}/dividends", headers: { "Host" => "flexile.dev" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        
        expect(json["pagination"]).to include(
          "current_page" => 1,
          "per_page" => 25,
          "total_pages" => 1,
          "total_count" => 0
        )
      end

      it "filters dividends by status" do
        paid_dividend = create(:dividend, company: company, dividend_round: dividend_round, 
                              company_investor: investor, status: "Paid")
        issued_dividend = create(:dividend, company: company, dividend_round: dividend_round, 
                                company_investor: investor, status: "Issued")

        get "/v1/companies/#{company.id}/dividends?status=Paid", headers: { "Host" => "flexile.dev" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        
        expect(json["dividends"].length).to eq(1)
        expect(json["dividends"].first["id"]).to eq(paid_dividend.id)
        expect(json["dividends"].first["status"]).to eq("Paid")
      end

      it "filters dividends by dividend_round_id" do
        other_round = create(:dividend_round, company: company)
        other_dividend = create(:dividend, company: company, dividend_round: other_round, 
                               company_investor: investor)
        target_dividend = create(:dividend, company: company, dividend_round: dividend_round, 
                                 company_investor: investor)

        get "/v1/companies/#{company.id}/dividends?dividend_round_id=#{dividend_round.id}", 
            headers: { "Host" => "flexile.dev" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        
        expect(json["dividends"].length).to eq(1)
        expect(json["dividends"].first["id"]).to eq(target_dividend.id)
      end

      it "supports pagination parameters" do
        create_list(:dividend, 30, company: company, dividend_round: dividend_round, 
                   company_investor: investor)

        get "/v1/companies/#{company.id}/dividends?page=2&per_page=10", 
            headers: { "Host" => "flexile.dev" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        
        expect(json["pagination"]).to include(
          "current_page" => 2,
          "per_page" => 10,
          "total_pages" => 3,
          "total_count" => 30
        )
        expect(json["dividends"].length).to eq(10)
      end

      it "limits per_page to maximum of 100" do
        get "/v1/companies/#{company.id}/dividends?per_page=200", 
            headers: { "Host" => "flexile.dev" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["pagination"]["per_page"]).to eq(100)
      end
    end

    context "when user is not authenticated" do
      before do
        allow(Current).to receive(:user).and_return(nil)
      end

      it "returns unauthorized error" do
        get "/v1/companies/#{company.id}/dividends", headers: { "Host" => "flexile.dev" }

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Unauthorized")
      end
    end

    context "when user is not authorized for the company" do
      it "returns forbidden error" do
        get "/v1/companies/#{company.id}/dividends", headers: { "Host" => "flexile.dev" }

        expect(response).to have_http_status(:forbidden)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Forbidden")
      end
    end

    context "when company does not exist" do
      before { administrator }

      it "returns not found error" do
        get "/v1/companies/999999/dividends", headers: { "Host" => "flexile.dev" }

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Company not found")
      end
    end
  end

  describe "GET /api/v1/companies/:company_id/dividends/:id" do
    context "when user is authenticated and authorized" do
      before { administrator }

      it "returns the specific dividend" do
        get "/v1/companies/#{company.id}/dividends/#{dividend.id}", 
            headers: { "Host" => "flexile.dev" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        
        expect(json["dividend"]["id"]).to eq(dividend.id)
        expect(json["dividend"]["status"]).to eq(dividend.status)
        expect(json["dividend"]["total_amount_cents"]).to eq(dividend.total_amount_in_cents)
        expect(json["dividend"]["qualified_amount_cents"]).to eq(dividend.qualified_amount_cents)
        expect(json["dividend"]["signed_release_at"]).to eq(dividend.signed_release_at)
        expect(json["dividend"]["dividend_round"]["id"]).to eq(dividend_round.id)
        expect(json["dividend"]["company_investor"]["id"]).to eq(investor.id)
      end

      it "returns not found for non-existent dividend" do
        get "/v1/companies/#{company.id}/dividends/999999", 
            headers: { "Host" => "flexile.dev" }

        expect(response).to have_http_status(:not_found)
      end
    end

    context "when user is not authenticated" do
      before do
        allow(Current).to receive(:user).and_return(nil)
      end

      it "returns unauthorized error" do
        get "/v1/companies/#{company.id}/dividends/#{dividend.id}", 
            headers: { "Host" => "flexile.dev" }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "Authorization for different user types" do
    context "when user is a company administrator" do
      before { administrator }

      it "allows access to dividends" do
        get "/v1/companies/#{company.id}/dividends", headers: { "Host" => "flexile.dev" }
        expect(response).to have_http_status(:ok)
      end
    end

    context "when user is a company investor" do
      before { investor }

      it "allows access to dividends" do
        get "/v1/companies/#{company.id}/dividends", headers: { "Host" => "flexile.dev" }
        expect(response).to have_http_status(:ok)
      end
    end

    context "when user has no relationship to the company" do
      it "denies access to dividends" do
        get "/v1/companies/#{company.id}/dividends", headers: { "Host" => "flexile.dev" }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end