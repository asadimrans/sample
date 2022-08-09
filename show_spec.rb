require 'rails_helper'

RSpec.describe 'V1::TeeTimes::Reservations::Show', type: :request do
  let(:call_api) { get "/api/v1/reservations/#{reservation_id}", params: params, headers: headers }
  let(:headers) { { 'Authorization' => jwt } }
  let(:params) { {} }
  let(:jwt) { '' }
  let(:reservation_id) { reservation&.id.to_i }
  let(:reservation) { nil }

  context 'With an invalid JWT' do
    it { expect(call_api && error).to match [:auth, :invalid_token, 'Invalid token'] }
  end

  context 'With a valid JWT' do
    let(:jwt) { create(:api_consumer).jwt }

    context 'with a reservation id' do
      let(:golf_course) { create :golf_course, :with_online_pricing }
      let(:reservation) { create :reservation, golf_course: golf_course }
      it 'succeeds and returns the expected data' do
        call_api
        expect(success)
        expect(json.keys).to match_array %w[connect_reservation_identifier id notes owner slots tee_time_identifier]
        expect(json['slots'].count).to eq 1
        expect(json['slots'].first.keys).to match_array %w[id golfer guest golfer_state holes payment_state position transportation]
        expect(json['slots'].first['golfer'].keys).to match_array %w[id first_name last_name email phone golfpay_identifier]
        expect(json['slots'].first['guest']).to be_nil
      end
    end

    context 'with an reservation id' do
      let(:reservation_id) { 0 }

      it { expect(call_api && error).to match [:db, :record_not_found, /Couldn't find Reservation with */] }
    end
  end
end
