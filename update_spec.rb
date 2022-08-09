require 'rails_helper'

RSpec.describe 'V1::TeeTimes::Reservations::Update', type: :request do
  let(:call_api) { patch "/api/v1/reservations/#{reservation_id}", params: params, headers: headers }
  let(:reservation_id) { reservation&.id || 0 }
  let(:reservation) { nil }
  let(:params) { required_params.merge(optional_params) }
  let(:required_params) { {} }
  let(:optional_params) { {} }
  let(:headers) { { 'Authorization' => jwt } }
  let(:jwt) { nil }
  let(:response_keys) { %w[id notes owner slots tee_time_identifier connect_reservation_identifier] }

  context 'With an invalid JWT' do
    let(:jwt) { "INVALID" }
    it { expect(call_api && error).to match [:auth, :invalid_token, 'Invalid token'] }
  end

  context 'With a valid JWT' do
    let(:jwt) { create(:api_consumer).jwt }

    context "Without all required params" do
      it { expect(call_api && error).to match [:validation, :validation_errors, /slots is missing/] }
    end

    context "With required params" do
      let(:required_params) { { paying_slot_id: paying_slot_id, slots: slots } }

      context "With a reservation with 3 unpaid unchecked in slots" do
        let(:golf_course) { create :golf_course, :with_online_pricing }
        let(:reservation) { create :reservation, additional_slots: 2, golf_course: golf_course }

        context "When checking in only the first slot" do
          let(:paying_slot) { reservation.slots[0] }
          let(:paying_slot_id) { paying_slot.id }
          let(:slots) { [{ id: paying_slot.id, paid: true }] }

          context "When clover API calls perform as expected" do
            before {
              allow_any_instance_of(Clover::CreateOrderService).to receive(:clover_create_order).and_return({ id: 123, }.with_indifferent_access)
              allow_any_instance_of(Clover::CreateOrderService).to receive(:clover_update_order_state)
              allow_any_instance_of(Clover::CreateOrderService).to receive(:clover_add_bulk_line_items_to_order)
              allow_any_instance_of(Clover::CreateOrderService).to receive(:clover_add_discounts_to_order)
              allow_any_instance_of(Clover::CreateOrderService).to receive(:clover_add_single_inventory_item_to_order)
              allow_any_instance_of(Clover::CreateOrderService).to receive(:ecommerce_clover_pay_with_tender)
            }

            it "succeeds, changes data and returns required keys and values" do
              expect {
                call_api
                expect(success)
                expect(reservation.slots.count).to eq 3
                expect(json.keys).to match_array response_keys
                expect(json[:slots].count).to eq reservation.slots.count
                expect(json[:slots].first.keys).to match_array %w[id position golfer_state payment_state golfer guest holes transportation]
                expect(paying_slot.reload.payment_amount).to eq paying_slot.total_price
              }
              .to change { paying_slot.reload.aasm_golfer_state }.from('reserved').to('checked_in')
              .and change { paying_slot.reload.aasm_payment_state }.from('unpaid').to('paid')
              .and not_change { reservation.slots[1] }
              .and not_change { reservation.slots[2] }
            end

            context "When paying slot is guest" do
              let(:paying_guest_slot) { create :slot, :with_a_guest, reservation: reservation, golf_course: golf_course }
              let(:paying_slot) { paying_guest_slot }
              let(:paying_slot_id) { paying_slot.id }
              let(:slots) { [{ id: paying_slot.id, paid: true }] }

              it "succeeds, changes data and returns required keys and values" do
                expect {
                  call_api
                  expect(success)
                  expect(reservation.slots.count).to eq 4
                  expect(json.keys).to match_array response_keys
                  expect(json[:slots].count).to eq reservation.slots.count
                  expect(json[:slots].first.keys).to match_array %w[id position golfer_state payment_state golfer guest holes transportation]
                }
                .to change { paying_slot.reload.aasm_golfer_state }.from('reserved').to('checked_in')
                .and change { paying_slot.reload.aasm_payment_state }.from('unpaid').to('paid')
                .and not_change { reservation.slots[0] }
                .and not_change { reservation.slots[1] }
                .and not_change { reservation.slots[2] }
              end
            end

            context "With attributes" do
              let(:optional_params) { { attributes: { connect_reservation_identifier: "GP-Connect#1234" } } }

              it "succeeds, changes data and returns required keys and values" do
                expect {
                  call_api
                  expect(success)
                  expect(reservation.slots.count).to eq 3
                  expect(json.keys).to match_array response_keys
                  expect(json[:slots].count).to eq reservation.slots.count
                  expect(json[:slots].first.keys).to match_array %w[id position golfer_state payment_state golfer guest holes transportation]
                  expect(json[:connect_reservation_identifier]).to eq "GP-Connect#1234"
                }
                .to change { paying_slot.reload.aasm_golfer_state }.from('reserved').to('checked_in')
                .and change { paying_slot.reload.aasm_payment_state }.from('unpaid').to('paid')
                .and not_change { reservation.slots[1] }
                .and not_change { reservation.slots[2] }
              end
            end

            context "With payment_details" do
              let(:payment_time) { Time.current.to_s }
              let(:payment_amount) { 12.91 }
              let(:payment_method) { "VISA" }
              let(:fop_last_4_digits) { "3456" }
              let(:optional_params) {{
                payment_details: {
                  amount: payment_amount,
                  payment_datetime: payment_time,
                  fop: payment_method,
                  fop_last_4_digits: fop_last_4_digits,
                }
              }}

              it "succeeds, changes data and returns required keys and values" do
                expect {
                  call_api
                  expect(success)
                  expect(reservation.slots.count).to eq 3
                  expect(json.keys).to match_array response_keys
                  expect(json[:slots].count).to eq reservation.slots.count
                  expect(json[:slots].first.keys).to match_array %w[id position golfer_state payment_state golfer guest holes transportation]
                  expect(paying_slot.reload.is_paying_slot?).to be_true
                  expect(paying_slot.reload.payment_amount).to eq payment_amount
                  expect(paying_slot.reload.payment_datetime).to eq payment_time
                  expect(paying_slot.reload.fop).to eq payment_method
                  expect(paying_slot.reload.fop_last_4_digits).to eq fop_last_4_digits
                }
                .to change { paying_slot.reload.aasm_golfer_state }.from('reserved').to('checked_in')
                .and change { paying_slot.reload.aasm_payment_state }.from('unpaid').to('paid')
                .and not_change { reservation.slots[1] }
                .and not_change { reservation.slots[2] }
              end
            end

            context "With notes" do
              let(:optional_params) { { notes: "This is a note." } }

              it "succeeds, changes data and returns required keys and values" do
                expect {
                  call_api
                  expect(success)
                  expect(reservation.slots.count).to eq 3
                  expect(json.keys).to match_array response_keys
                  expect(json[:slots].count).to eq reservation.slots.count
                  expect(json[:slots].first.keys).to match_array %w[id position golfer_state payment_state golfer guest holes transportation]
                  expect(json[:notes]).to eq "This is a note."
                }
                .to change { paying_slot.reload.aasm_golfer_state }.from('reserved').to('checked_in')
                .and change { paying_slot.reload.aasm_payment_state }.from('unpaid').to('paid')
                .and not_change { reservation.slots[1] }
                .and not_change { reservation.slots[2] }
              end
            end

            context "when a slot in the request is already paid for" do
              before { reservation.slots.first.update_column :aasm_payment_state, :paid }

              it { expect(call_api && error).to match [:reservation, :payment_already_initiated, /Payment has already been initiated/] }
            end

            context "when clover_connect_tender_identifier is blank" do
              before { Property.current.update!(clover_connect_tender_identifier: nil) }

              it { expect(call_api && error).to match [:reservation, :clover_error, /Property must have a clover_connect_tender_identifier but it is nil/] }
            end
          end
        end
      end
    end
  end
end
