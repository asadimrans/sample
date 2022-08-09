require 'rails_helper'

RSpec.describe 'V1::TeeTimes::Reservations::Create', type: :request do
  let(:call_api) { post "/api/v1/tee_times/#{tee_time_identifier}/reservations", params: params, headers: headers }
  let(:tee_time_identifier) { 0 }
  let(:params) { required_params.merge(optional_params) }
  let(:required_params) { {} }
  let(:optional_params) { {} }
  let(:headers) { { 'Authorization' => jwt } }
  let(:jwt) { nil }

  context 'With an invalid JWT' do
    let(:jwt) { "INVALID" }
    it { expect(call_api && error).to match [:auth, :invalid_token, 'Invalid token'] }
  end

  context 'With a valid JWT' do
    let(:jwt) { create(:api_consumer).jwt }

    context "Without all required params" do
      it { expect(call_api && error).to match [:validation, :validation_errors, "slots is missing"] }
    end

    context "With required params" do
      let(:required_params) { { slots: slots, reservation_owner_golfpay_identifier: reservation_owner_golfpay_identifier } }
      let(:slots) { [{ holes: '18_holes',
                       transportation: 'cart',
                       slot_fees_attributes: [
                        { kind: 'green', amount: 4.56, tax: 1.23, description: "A Fee" },
                        { kind: 'cart', amount: 7.89, tax: 2.34, description: "A Fee" }
                       ],
                       fee_summary: "Fee summary",
                       golfer_attributes: golfer_attributes,
                       guest_attributes: guest_attributes
                      }.compact] }
      let(:golfer_attributes) { { first_name: Faker::Name.first_name, email: Faker::Internet.unique.email } }
      let(:guest_attributes) { nil }
      let(:reservation_owner_golfpay_identifier) { nil }

      context "With an invalid tee_time_identifier" do
        it { expect(call_api && error).to match [:reservation, :record_not_found, /Invalid tee time identifier/] }
      end

      context 'with an in-season golf course with prices for all times' do
        let!(:golf_course) { create :golf_course, :with_online_pricing }

        context "With a valid tee_time_identifier" do
          let(:available_tee_time) { golf_course.decorate(context: { date: Date.tomorrow }).available_online_tee_times.sample }
          let(:tee_time_identifier) { available_tee_time.identifier.to_s }

          it "succeeds, changes data and returns required keys and values" do
            expect {
              call_api
              expect(success)
              expect(json.keys).to match_array %w[connect_reservation_identifier id notes owner slots tee_time_identifier]
              expect(json[:slots].count).to eq slots.count
              expect(json[:slots].first.keys).to match_array %w[id position golfer_state payment_state golfer guest holes transportation]
              expect(json[:slots].first[:golfer]).to be_present
              expect(json[:slots].first[:guest]).to be_nil
            }
            .to change { golf_course.reservations.count }.by(1)
            .and change { golf_course.slots.count }.by(slots.count)
          end

          context "With a guest golfer" do
            let(:golfer_attributes) { nil }
            let(:guest_attributes) { { name: "Guest 1", phone: "602-555-0100" } }

            it "succeeds, changes data and returns required keys and values" do
              expect {
                call_api
                expect(success)
                expect(json.keys).to match_array %w[connect_reservation_identifier id notes owner slots tee_time_identifier]
                expect(json[:slots].count).to eq slots.count
                expect(json[:slots].first.keys).to match_array %w[id position golfer_state payment_state golfer guest holes transportation]
                expect(json[:slots].first[:golfer]).to be_nil
                expect(json[:slots].first[:guest][:name]).to eq "Guest 1"
                expect(json[:slots].first[:guest][:phone]).to eq "602-555-0100"
              }
              .to change { golf_course.reservations.count }.by(1)
              .and change { golf_course.slots.count }.by(slots.count)
              .and not_change { Golfer.count }
            end
          end

          context "With no guest and no golfer" do
            let(:golfer_attributes) { nil }
            let(:guest_attributes) { nil }

            it { expect(call_api && error).to match [:validation, :validation_errors, /exactly one parameter must be provided/] }
          end

          context "With notes" do
            let(:optional_params) { { notes: "This is a note." } }

            it "succeeds, changes data and returns required keys and values" do
              expect {
                call_api
                expect(success)
                expect(json.keys).to match_array %w[connect_reservation_identifier id notes owner slots tee_time_identifier]
                expect(json[:slots].count).to eq slots.count
                expect(json[:slots].first.keys).to match_array %w[id position golfer_state payment_state golfer guest holes transportation]
                expect(json[:notes]).to eq "This is a note."
              }
              .to change { golf_course.reservations.count }.by(1)
              .and change { golf_course.slots.count }.by(slots.count)
            end
          end

          context "With a new (to us) golfer" do
            context "When the golfer doesn't the required fields" do
              let(:golfer_attributes) { { first_name: Faker::Name.first_name } }
              it { expect(call_api && error).to match [:validation, :validation_errors, /are missing/] }
            end

            context "With valid golfer data" do
              let(:golfer_attributes) { { first_name: Faker::Name.first_name, email: Faker::PhoneNumber.unique.phone_number } }
              it "succeeds and adds the golfer to our database" do
                expect {
                  call_api
                  expect(success)
                }.to change { Golfer.count }.by(1)
              end
            end
          end

          context "When the golfer's golfpay_identifier matches one in our database" do
            let!(:existing_golfer) { create :golfer, golfpay_identifier: '123' }
            let(:golfer_attributes) { { first_name: "New First Name", email: Faker::PhoneNumber.unique.phone_number, golfpay_identifier: existing_golfer.golfpay_identifier } }

            it "succeeds and associates to the existing golfer" do
              expect {
                call_api
                expect(success)
                expect(json[:slots].first['golfer']['id']).to eq existing_golfer.id
                expect(json[:slots].first['golfer']['golfpay_identifier']).to eq '123'
                expect(json[:slots].first['golfer']['first_name']).to eq existing_golfer.first_name
              }.not_to change { Golfer.count }
            end
          end

          context "When the golfer's email matches one in our database, even if case doesn't match" do
            let!(:existing_golfer) { create :golfer, email: "someone@somewhere.com" }
            let(:golfer_attributes) { { first_name: "Some First Name", email: "Someone@SOMEWHERE.com" } }

            it "succeeds and associates to the existing golfer" do
              expect {
                call_api
                expect(success)
                expect(json[:slots].first['golfer']['id']).to eq existing_golfer.id
              }.not_to change { Golfer.count }
            end
          end

          context "When the golfer's phone number matches one in our database, even if punctuation doesn't match" do
            let!(:existing_golfer) { create :golfer, phone: "1 (602) 555-1212" }
            let(:golfer_attributes) { { first_name: "Some First Name", phone: "1-602-555-1212" } }

            it "succeeds and associates to the existing golfer" do
              expect {
                call_api
                expect(success)
                expect(json[:slots].first['golfer']['id']).to eq existing_golfer.id
              }.not_to change { Golfer.count }
            end
          end

          context "When the golfer's phone number and email matches one in our database" do
            let!(:existing_golfer) { create :golfer, phone: "1 (602) 555-1212" }
            let(:golfer_attributes) { { first_name: "Some First Name", email: existing_golfer.email, phone: existing_golfer.phone } }

            it "succeeds and associates to the existing golfer" do
              expect {
                call_api
                expect(success)
                expect(json[:slots].first['golfer']['id']).to eq existing_golfer.id
              }.not_to change { Golfer.count }
            end
          end

          context "When the golfer's phone number matches, but their supplied email doesn't match" do
            let!(:existing_golfer) { create :golfer, phone: "1 (602) 555-1212" }
            let(:golfer_attributes) { { first_name: "Some First Name", email: "another@email.com", phone: existing_golfer.phone } }

            it "succeeds and associates to a existing golfer" do
              expect {
                call_api
                expect(success)
                expect(json[:slots].first['golfer']['id']).to eq existing_golfer.id
              }.not_to change { Golfer.count }
            end
          end

          context "When the golfer's email matches, but their supplied phone number doesn't match" do
            let!(:existing_golfer) { create :golfer, phone: "1 (602) 555-1212" }
            let(:golfer_attributes) { { first_name: "Some First Name", email: existing_golfer.email, phone: "12125558899" } }

            it "succeeds and associates to the existing golfer" do
              expect {
                call_api
                expect(success)
                expect(json[:slots].first['golfer']['id']).to eq existing_golfer.id
              }.not_to change { Golfer.count }
            end
          end

          context "When there isn't room on the tee time" do
            let!(:reservation) { create :reservation, tee_time: available_tee_time, additional_slots: 4 }
            it { expect(call_api && error).to match [:reservation, :no_available_slots, "Tee time doesn't have room"] }
          end

          context "With an invalid reservation_owner_golfpay_identifier" do
            let(:reservation_owner_golfpay_identifier) { "INVALID" }
            it { expect(call_api && error).to match [:reservation, :record_not_found, "reservation_owner_golfpay_identifier not found"] }
          end
        end
      end
    end
  end
end
