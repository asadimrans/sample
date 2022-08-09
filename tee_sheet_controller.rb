class TeeSheetController < AuthenticatedUserController
  include SetInboundGolfers
  include SetOpenGolfCourses
  include TeeSheetHelper

  skip_before_action :authenticate_user!, only: :send_offline_tee_time

  def index
    @starter_golf_course_id = params[:golf_course_id]
    @date = params[:date] ? Time.parse(params[:date]).to_date : current_property.current_time.to_date
    @property = current_property.decorate(context: { date: @date })
    @daily_note = @property.daily_note
    all_ivr_sessions = @property.ivr_sessions.today
    all_message_sessions = @property.message_sessions.today

    @ivr_sessions = all_ivr_sessions.select{|p| p.status == 'connect' }.sort_by(&:updated_at)&.reverse!
    @message_sessions = all_message_sessions.select{|p| p.active? }.sort_by(&:updated_at)&.reverse!

    @open_inbound_golfer_sessions = all_ivr_sessions.select{|p| p.is_closed != true } + all_message_sessions.select{|p| p.is_closed != true }

    disconnected_ivr = all_ivr_sessions.select{|p| p.status == 'disconnect' }.sort_by(&:updated_at)&.reverse!
    inactive_ivr = all_message_sessions.select{|p| p.inactive? }.sort_by(&:updated_at)&.reverse!
    
    @pagy, @disconnected_ivr = pagy_array(disconnected_ivr, page: 1, items: 5)
    @mpagy, @inactive_ivr = pagy_array(inactive_ivr, page: 1, items: 5)

    @big_data = generate_big_data(@tee_sheet_golf_courses, @date)
  end

  def offline_tee_time
    return redirect_to root_path unless (params[:golf_course_id].present? && params[:date].present?)

    url = send_offline_tee_time_url(date: params[:date], golf_course_id: params[:golf_course_id])
    pdf = Dhalang::PDF.get_from_url(url, {navigationTimeout: 500000,  width: '2500px', format: 'A3'})

    file_name = "online_report"
    send_data pdf , filename: "#{file_name}.pdf", type: 'application/pdf', disposition: :inline
  end


  def send_offline_tee_time
    @date = params[:date] ? Time.parse(params[:date]).to_date : current_property.current_time.to_date
    @golf_course = GolfCourse.find(params[:golf_course_id]).decorate(context: { date: @date })
    @tee_sheet_items = @golf_course.daily_tee_sheet_items_printable.each_slice( 3 ).to_a
  end

  def generate_big_data(golf_coureses, date)
    big_data = {}
    golf_coureses.each do |golf_course|
      season = golf_course.season_with_time_frames(@date.beginning_of_day)
      slot_range = generate_slot_ranges(golf_course, date, season)
      _time_frames =  season&.time_frames
      big_data.merge!({"golf_course_#{golf_course.id}" => { season: season, time_frames: _time_frames, slot_range: slot_range} })
    end
    big_data.merge!({"active_filter" => true })
    big_data
  end

  def generate_slot_ranges(golf_course, date, season)
    slot_range = []
    items = items(golf_course, date)
    if date == Date.today 
      if current_property.local_time(DateTime.now).strftime("%I:%M %p").include? "AM"
        golf_course_time_slots = golf_course.am_slot_range(date)
        am_items = items_from_beginning_date(golf_course,date)
        golf_course.update(time_filter: "AM")
      else
        golf_course_time_slots = golf_course.pm_slot_range(date)
        pm_items = items_from_end_date(golf_course,date)
        golf_course.update(time_filter: "PM")
      end
    else
      # key = "#{current_property.id}_#{golf_course.id}_#{date}"
      # value = Rails.cache.read(key)
      # if !value.nil?
      #   golf_course.update(time_filter: "ALL")
      #   am_items = items_from_beginning_date(golf_course,date)
      #   pm_items = items_from_end_date(golf_course,date)
      #   golf_course_time_slots = golf_course.slot_range(date)
      # else
      #   golf_course.update(time_filter: "AM")
      #   am_items = items_from_beginning_date(golf_course,date)
      #   golf_course_time_slots = golf_course.am_slot_range(date)
      # end
      golf_course.update(time_filter: "AM")
      am_items = items_from_beginning_date(golf_course,date)
      golf_course_time_slots = golf_course.am_slot_range(date)
    end  
    
    golf_course_time_slots.each do |slot|
      slot_items = selected_items_in_slot(golf_course, date, slot, items)
      # slot_items = items_in_slot(golf_course, date, slot)
      if slot_items.blank?
        time = Time.at(slot).utc
        next if tournament?(golf_course, date, slot)
        next if block?(golf_course, date, slot)
        slot_data = Rails.cache.fetch([:v5, :new_tee_sheet_items, slot, time, golf_course, date, season]) do
           slot_data = TeeSheetItem.new(starts_at: time, tee_sheet_itemable: TeeTime.new(), golf_course: golf_course, property: golf_course.property)
        end
        slot_range << slot_data
      else
        slot_range << slot_items
      end
    end
    
    # if date == Date.today
    #   if current_property.local_time(DateTime.now).strftime("%I:%M %p").include? "AM"
    #     new_items = items_from_beginning_date(golf_course,date)
    #   else
    #     new_items = items_from_end_date(golf_course,date)
    #   end
    # end
    # slot_range = slot_range.push(new_items) if new_items.present?
    slot_range = slot_range.push(am_items) if am_items.present?
    slot_range = slot_range.push(pm_items) if pm_items.present?
    slot_range = slot_range.flatten.sort_by(&:starts_at) if slot_range.present?
    # Rails.logger.info "=========slot_range_controller====#{slot_range}==========="
    slot_range.flatten
  end
end
