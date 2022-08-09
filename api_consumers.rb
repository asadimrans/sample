ActiveAdmin.register APIConsumer do
  menu false

  permit_params :description, webhook_endpoints_attributes: [:_destroy, :id, :target_url, events: []]

  index do
    selectable_column
    id_column
    column :description
    column :webhooks do |resource|
      resource.webhook_endpoints.size
    end
    actions
  end

  show do
    attributes_table do
      row :id
      row :description
      row :shared_secret
      row :jwt
    end
    attributes_table title: "Webhooks" do
      row :endpoints do |resource|
        resource.webhook_endpoints.each do |we|
          dl do
            dt "Endpoint"
            dd we.target_url
            dt "Events"
            dd we.events.join(', ')
            br
          end
        end
        nil
      end
    end
  end

  form do |f|
    f.inputs do
      f.input :description
    end

    f.inputs "Webhooks" do
      f.has_many :webhook_endpoints, new_record: true, allow_destroy: true do |w|
        w.input :target_url, placeholder: "https://somewhere.com/360/webhook", hint: "All events will use the POST action on this URL"
        w.input :events, as: :check_boxes, collection: Webhook::Event::EVENT_TYPES
      end
    end

    f.submit
  end
end
