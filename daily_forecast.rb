# frozen_string_literal: true

class DailyForecast < ApplicationRecord
  acts_as_tenant(:property)

  validates :property_id, presence: true
  validates :day, presence: true
  validates_uniqueness_to_tenant :day

  def self.pull(propy)
    data = propy.weather_info
    return if data['daily'].blank?

    data['daily'].each do |daily|
      at = daily['dt'].in_time_zone(propy.local_time_zone).to_date
      forecast = DailyForecast.where(property_id: propy.id, day: at).first_or_initialize
      forecast.map_weather(daily)
      forecast.save!
    end
  end

  def self.at(day)
    # TODO: RC: Convert to accept ranges
    day = day.to_date unless day.is_a? Date
    Rails.cache.fetch([:v4, :daily_weather_info, day], expires_in: 4.hours) do
      Property.current.daily_forecasts.find_by_day(day)
    end
  end

  def map_weather(data)
    write_attribute(:high_temp, data['temp']['max'])
    write_attribute(:low_temp, data['temp']['min'])
    write_attribute(:icon, data['weather'].first['icon'])
  end
end
# {"dt"=>2022-02-02 18:00:00 UTC,
#     "sunrise"=>2022-02-02 12:42:23 UTC,
#     "sunset"=>2022-02-02 23:29:38 UTC,
#     "temp"=>
#      {"day"=>63.84,
#       "min"=>62.8,
#       "max"=>63.88,
#       "night"=>63.16,
#       "eve"=>63.32,
#       "morn"=>63.54},
#     "feels_like"=>{"day"=>63.97, "night"=>63.73, "eve"=>63.77, "morn"=>63.54},
#     "pressure"=>1017,
#     "humidity"=>86,
#     "dew_point"=>59.58,
#     "wind_speed"=>27.04,
#     "wind_deg"=>131,
#     "wind_gust"=>39.62,
#     "weather"=>
#      [{"id"=>500,
#        "main"=>"Rain",
#        "description"=>"light rain",
#        "icon_uri"=>#<URI::HTTP http://openweathermap.org/img/wn/10d@2x.png>,
#        "icon"=>"10d"}],
#     "clouds"=>100,
#     "rain"=>5.89,
#     "uvi"=>1.73}
