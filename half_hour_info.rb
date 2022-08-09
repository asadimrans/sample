class HalfHourInfo
  attr_reader :location, :from_time, :to_time, :forecast_date_range

  def initialize(location:, from_time:, to_time:, forecast_date_range:)
    @location = location
    @from_time = from_time
    @to_time = to_time
    @forecast_date_range = forecast_date_range
  end

  def half_hourly_without_weather
    min_time = from_time.beginning_of_hour.to_i
    max_time = to_time.end_of_hour.to_i
    (min_time .. max_time).step(30.minutes).map do |unix_time|
      OpenStruct.new({
        time: Time.at(unix_time),
        weather: nil,
        error_message: nil
      })
    end
  end

  def half_hourly(weather: true)
    min_time = from_time.beginning_of_hour.to_i
    max_time = to_time.end_of_hour.to_i
    (min_time .. max_time).step(30.minutes).map do |unix_time|
      time = Time.at(unix_time)

      # Only call the weather service if we're returning weather info
      result = weather ? WeatherNearTimeService.call(location: location, time: time) : nil

      OpenStruct.new({
        time: time,
        weather: result&.success? ? result.weather : nil,
        error_message: result&.message
      })
    end

  end

  def daily_forecasts
    forecast_date_range.map do |date|
      result = WeatherForecastForDayService.call location: location, date: date

      OpenStruct.new({
        date: date,
        weather: result.success? ? result.weather : nil,
        error_message: result.message
      })
    end
  end

  def alerts
    result = WeatherAlertsService.call location: location

    result.success? ? result.alerts : []
  end

  private

  # Can be used as part of the alerts response for testing the UI
  def dummy_data
    OpenStruct.new(
      event: "Test",
      start: Time.current,
      end: Time.current + 1.day,
      description: "Lorem ipsum"
    )
  end
end
