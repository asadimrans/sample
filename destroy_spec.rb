require 'rails_helper'

RSpec.describe 'V1::TeeTimes::Reservations::Destroy', type: :request do
  let(:golf_course) { create :golf_course, :with_online_pricing }
  let(:reservation) { create :reservation, golf_course: golf_course, date: 3.days.from_now, index: 1 }
  let(:reservation_id) { reservation.id }
  let(:call_api) { delete "/api/v1/reservations/#{reservation_id}", headers: headers }
  let(:headers) { { 'Authorization' => jwt } }
  let(:jwt) { '' }

  context 'With an invalid JWT' do
    it { expect(call_api && error).to match [:auth, :invalid_token, 'Invalid token'] }
  end

  context 'With a valid JWT' do
    let(:jwt) { create(:api_consumer).jwt }

    context 'with a tee time and reservation' do
      it 'succeeds and returns the expected data' do
        call_api
        expect(success)
        expect(json.keys).to match_array %w[connect_reservation_identifier id notes owner slots tee_time_identifier]
        expect(json['owner'].keys).to match_array %w[id golfpay_identifier first_name last_name email phone]
        expect(json['slots'].first.keys).to match_array %w[id golfer guest golfer_state holes payment_state position transportation]
        expect(json['slots'].first['golfer'].keys).to match_array %w[id golfpay_identifier first_name last_name email phone]
        expect(json['slots'].first['guest']).to be_nil
      end
    end

    context 'with a paid slot on the reservation' do
      before { reservation.slots.first.update(aasm_payment_state: :paid) }

      it { expect(call_api && error).to match [:reservation, :has_paid_slots, /Sorry the reservation already has paid slots/] }
    end

    context 'with an invalid reservation' do
      let(:reservation_id) { 0 }

      it { expect(call_api && error).to match [:db, :record_not_found, /Couldn't find Reservation with 'id'=/] }
    end
  end
end
