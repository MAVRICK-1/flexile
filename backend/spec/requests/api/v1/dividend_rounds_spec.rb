# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "Api::V1::DividendRounds", type: :request do
  let(:company) { create(:company) }
  let(:user) { create(:user) }
  let(:administrator) { create(:company_administrator, company: company, user: user) }
  let(:investor) { create(:company_investor, company: company, user: user) }
  let(:dividend_round) { create(:dividend_round, company: company) }

  before do
    # Mock Clerk authentication
    allow_any_instance_of(Api::V1::DividendRoundsController).to receive(:clerk).and_return(
      double(user?: true, user_id: user.clerk_id)
    )
    allow(User).to receive(:find_by).with(clerk_id: user.clerk_id).and_return(user)
    allow(Current).to receive(:user).and_return(user)
  end

  describe "GET /api/v1/companies/:company_id/dividend_rounds" do
    context "when user is authenticated and authorized" do
      before { administrator } # Create administrator association

      it "returns dividend rounds for the company" do
        dividend_round # Create dividend round
        get "/v1/companies/#{company.id}/dividend_rounds", headers: { "Host" => "flexile.dev" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        
        expect(json["dividend_rounds"]).to be_an(Array)
        expect(json["dividend_rounds"].length).to eq(1)
        expect(json["dividend_rounds"].first["id"]).to eq(dividend_round.id)
        expect(json["dividend_rounds"].first["external_id"]).to eq(dividend_round.external_id)
        expect(json["dividend_rounds"].first["status"]).to eq(dividend_round.status)
        expect(json["dividend_rounds"].first["total_amount_cents"]).to eq(dividend_round.total_amount_in_cents)
        expect(json["dividend_rounds"].first["number_of_shares"]).to eq(dividend_round.number_of_shares)
        expect(json["dividend_rounds"].first["ready_for_payment"]).to eq(dividend_round.ready_for_payment)
      end

      it "orders dividend rounds by issued_at descending" do
        older_round = create(:dividend_round, company: company, issued_at: 1.week.ago)
        newer_round = create(:dividend_round, company: company, issued_at: 1.day.ago)

        get "/v1/companies/#{company.id}/dividend_rounds", headers: { "Host" => "flexile.dev" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        
        expect(json["dividend_rounds"].length).to eq(2)
        expect(json["dividend_rounds"].first["id"]).to eq(newer_round.id)
        expect(json["dividend_rounds"].last["id"]).to eq(older_round.id)
      end

      it "includes pagination metadata" do
        get "/v1/companies/#{company.id}/dividend_rounds", headers: { "Host" => "flexile.dev" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        
        expect(json["pagination"]).to include(
          "current_page" => 1,
          "per_page" => 25,
          "total_pages" => 1,
          "total_count" => 0
        )
      end

      it "filters dividend rounds by status" do
        paid_round = create(:dividend_round, company: company, status: "Paid")
        issued_round = create(:dividend_round, company: company, status: "Issued")

        get "/v1/companies/#{company.id}/dividend_rounds?status=Paid", 
            headers: { "Host" => "flexile.dev" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        
        expect(json["dividend_rounds"].length).to eq(1)
        expect(json["dividend_rounds"].first["id"]).to eq(paid_round.id)
        expect(json["dividend_rounds"].first["status"]).to eq("Paid")
      end

      it "filters dividend rounds by ready_for_payment" do
        ready_round = create(:dividend_round, company: company, ready_for_payment: true)
        not_ready_round = create(:dividend_round, company: company, ready_for_payment: false)

        get "/v1/companies/#{company.id}/dividend_rounds?ready_for_payment=true", 
            headers: { "Host" => "flexile.dev" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        
        expect(json["dividend_rounds"].length).to eq(1)
        expect(json["dividend_rounds"].first["id"]).to eq(ready_round.id)
        expect(json["dividend_rounds"].first["ready_for_payment"]).to be(true)
      end

      it "supports pagination parameters" do
        create_list(:dividend_round, 30, company: company)

        get "/v1/companies/#{company.id}/dividend_rounds?page=2&per_page=10", 
            headers: { "Host" => "flexile.dev" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        
        expect(json["pagination"]).to include(
          "current_page" => 2,
          "per_page" => 10,
          "total_pages" => 3,
          "total_count" => 30
        )
        expect(json["dividend_rounds"].length).to eq(10)
      end

      it "includes dividends_count in response" do
        create_list(:dividend, 3, company: company, dividend_round: dividend_round, 
                   company_investor: investor)

        get "/v1/companies/#{company.id}/dividend_rounds", headers: { "Host" => "flexile.dev" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        
        expect(json["dividend_rounds"].first["dividends_count"]).to eq(3)
      end
    end

    context "when user is not authenticated" do
      before do
        allow(Current).to receive(:user).and_return(nil)
      end

      it "returns unauthorized error" do
        get "/v1/companies/#{company.id}/dividend_rounds", headers: { "Host" => "flexile.dev" }

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Unauthorized")
      end
    end

    context "when user is not authorized for the company" do
      it "returns forbidden error" do
        get "/v1/companies/#{company.id}/dividend_rounds", headers: { "Host" => "flexile.dev" }

        expect(response).to have_http_status(:forbidden)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Forbidden")
      end
    end

    context "when company does not exist" do
      before { administrator }

      it "returns not found error" do
        get "/v1/companies/999999/dividend_rounds", headers: { "Host" => "flexile.dev" }

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Company not found")
      end
    end
  end

  describe "GET /api/v1/companies/:company_id/dividend_rounds/:id" do
    context "when user is authenticated and authorized" do
      before { administrator }

      it "returns the specific dividend round with dividends" do
        dividend = create(:dividend, company: company, dividend_round: dividend_round, 
                         company_investor: investor)

        get "/v1/companies/#{company.id}/dividend_rounds/#{dividend_round.id}", 
            headers: { "Host" => "flexile.dev" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        
        dividend_round_data = json["dividend_round"]
        expect(dividend_round_data["id"]).to eq(dividend_round.id)
        expect(dividend_round_data["external_id"]).to eq(dividend_round.external_id)
        expect(dividend_round_data["status"]).to eq(dividend_round.status)
        expect(dividend_round_data["total_amount_cents"]).to eq(dividend_round.total_amount_in_cents)
        
        # Check that dividends are included
        expect(dividend_round_data["dividends"]).to be_an(Array)
        expect(dividend_round_data["dividends"].length).to eq(1)
        expect(dividend_round_data["dividends"].first["id"]).to eq(dividend.id)
        expect(dividend_round_data["dividends"].first["status"]).to eq(dividend.status)
        expect(dividend_round_data["dividends"].first["company_investor"]["id"]).to eq(investor.id)
      end

      it "returns dividend round without dividends when none exist" do
        get "/v1/companies/#{company.id}/dividend_rounds/#{dividend_round.id}", 
            headers: { "Host" => "flexile.dev" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        
        expect(json["dividend_round"]["dividends"]).to eq([])
      end

      it "returns not found for non-existent dividend round" do
        get "/v1/companies/#{company.id}/dividend_rounds/999999", 
            headers: { "Host" => "flexile.dev" }

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Dividend round not found")
      end
    end

    context "when user is not authenticated" do
      before do
        allow(Current).to receive(:user).and_return(nil)
      end

      it "returns unauthorized error" do
        get "/v1/companies/#{company.id}/dividend_rounds/#{dividend_round.id}", 
            headers: { "Host" => "flexile.dev" }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "Authorization for different user types" do
    context "when user is a company administrator" do
      before { administrator }

      it "allows access to dividend rounds" do
        get "/v1/companies/#{company.id}/dividend_rounds", headers: { "Host" => "flexile.dev" }
        expect(response).to have_http_status(:ok)
      end
    end

    context "when user is a company investor" do
      before { investor }

      it "allows access to dividend rounds" do
        get "/v1/companies/#{company.id}/dividend_rounds", headers: { "Host" => "flexile.dev" }
        expect(response).to have_http_status(:ok)
      end
    end

    context "when user has no relationship to the company" do
      it "denies access to dividend rounds" do
        get "/v1/companies/#{company.id}/dividend_rounds", headers: { "Host" => "flexile.dev" }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end