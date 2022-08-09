class V1::AuthenticatedEndpoints < Grape::API
  before { authenticate_request! }

  mount V1::Properties
  mount V1::GolfCourses
  mount V1::TeeTimes
  mount V1::Slots
  mount V1::IvrSession
  mount V1::MessageSession
  mount V1::Golfers
  mount V1::InventoryItems
end
