# frozen_string_literal: true

class HourlyForecast < ApplicationRecord
  acts_as_tenant(:property)

  validates :property_id, presence: true
  validates :day, presence: true
  validates :interval, presence: true # , uniqueness: { scope: %i[day property_id] }
  # validates_uniqueness_to_tenant :interval, { scope: :day }

  def self.pull(propy)
    data = propy.weather_info
    return if data['hourly'].blank?

    data['hourly'].each do |hour|
      begin
        at = hour['dt'].in_time_zone(propy.local_time_zone)
        date = at.to_date
        interval = at.hour * 100
        forecast = HourlyForecast.where(property_id: propy.id, day: date, interval: interval).first_or_initialize
        forecast.map_weather(hour)
        forecast.save!
      rescue TypeError => e
        puts e.message
        puts hour['dt']
      end
    end
  end

  def self.at(time)
    time = time.in_time_zone(Property.current.local_time_zone)
    date = time.to_date
    interval = time.hour * 100
    Rails.cache.fetch([:v4, :hourly_weather_info, date, interval], expires_in: 4.hours) do
      Property.current.hourly_forecasts.find_by_day_and_interval(date, interval)
    end
  end

  def pop
    # TODO: RC: This is wrong
    temp.present? ? temp : 0
    # {weather['temp'].present? ? weather['temp']&.to_f&.round : 0}%  <- original
  end

  def wind_direction
    return '' if wind_deg.blank?

    cardnals = %w[North North-East East South-East South South-West West North-West]
    cardnals[wind_deg / 45]
  end

  def visibility
    # convert to miles, 10000 meters as a default for missing data
    value = read_attribute(:visibility) || 10_000
    (value / 1609).to_i
  end

  def map_weather(data)
    # gets one hour of data then auto maps it
    data.each_key do |key|
      next unless self.class.has_attribute?(key)

      write_attribute(key, data[key])
    end
    write_attribute(:icon, data['weather'].first['icon'])
    write_attribute(:description, data['weather'].first['description'])
    # "dt"=>2022-02-02 06:00:00 UTC,
    # "temp"=>62.6,
    # "feels_like"=>62.37,
    # "pressure"=>1017,
    # "humidity"=>81,
    # "dew_point"=>56.7,
    # "clouds"=>96,
    # "visibility"=>10000,
    # "wind_speed"=>27.02,
    # "wind_deg"=>128,
    # "wind_gust"=>38.32,
    # "weather"=>
    #  [{"id"=>804,
    #    "main"=>"Clouds",
    #    "description"=>"overcast clouds",
    #    "icon_uri"=>#<URI::HTTP http://openweathermap.org/img/wn/04n@2x.png>,
    #    "icon"=>"04n"}],

  end
end
