require 'rails_helper'

RSpec.describe 'API::V1::GolfCourses::Index', type: :request do
  let(:call_api) { get '/api/v1/golf_courses', params: params, headers: headers }
  let(:headers) { { 'Authorization' => jwt } }
  let(:params) { {} }
  let(:jwt) { "" }

  context "With an invalid JWT" do
    it { expect(call_api && error).to match [:auth, :invalid_token, "Invalid token"] }
  end

  context "With a valid JWT" do
    let(:jwt) { create(:api_consumer).jwt }

    context "with 2 golf courses" do
      let!(:golf_courses) { create_list :golf_course, 2 }

      it "succeeds and returns the expected data" do
        call_api
        expect(success)
        expect(json.length).to eq 2
        expect(json.first.keys).to match_array %w[id name description services identifier length_in_yards year_built rating slope par hole_count cart_rental]
      end
    end
  end
end
