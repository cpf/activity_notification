require 'dynamoid'
require 'activity_notification/apis/notification_api'

module ActivityNotification
  module ORM
    module Dynamoid
      # Notification model implementation generated by ActivityNotification.
      class Notification
        include ::Dynamoid::Document
        include ActiveModel::AttributeAssignment
        include GlobalID::Identification
        include DynamoidExtension
        include Common
        include Renderable
        include Association
        include NotificationApi

        table name: ActivityNotification.config.notification_table_name, key: :id

        # Belongs to target instance of this notification as polymorphic association using composite key.
        # @scope instance
        # @return [Object] Target instance of this notification
        belongs_to_composite_xdb_record :target, store_with_associated_records: true

        # Belongs to notifiable instance of this notification as polymorphic association using composite key.
        # @scope instance
        # @return [Object] Notifiable instance of this notification
        belongs_to_composite_xdb_record :notifiable, store_with_associated_records: true

        # Belongs to group instance of this notification as polymorphic association using composite key.
        # @scope instance
        # @return [Object] Group instance of this notification
        belongs_to_composite_xdb_record :group

        field :key,            :string
        field :parameters,     :raw,      default: {}
        field :opened_at,      :datetime
        field :group_owner_id, :string

        # Belongs to group owner notification instance of this notification.
        # Only group member instance has :group_owner value.
        # Group owner instance has nil as :group_owner association.
        # @scope instance
        # @return [Notification] Group owner notification instance of this notification
        belongs_to :group_owner, { class_name: "ActivityNotification::Notification", foreign_key: :group_owner_id }.merge(Rails::VERSION::MAJOR >= 5 ? { optional: true } : {})

        # Customized method that belongs to group owner notification instance of this notification.
        # @raise [Errors::RecordNotFound] Record not found error
        # @return [Notification] Group owner notification instance of this notification
        def group_owner
          group_owner_id.nil? ? nil : Notification.find(group_owner_id)
        end

        # Has many group member notification instances of this notification.
        # Only group owner instance has :group_members value.
        # Group member instance has nil as :group_members association.
        # @scope instance
        # @return [Dynamoid::Criteria::Chain] Database query of the group member notification instances of this notification
        # has_many   :group_members, class_name: "ActivityNotification::Notification", foreign_key: :group_owner_id
        def group_members
          Notification.where(group_owner_id: id)
        end

        # Belongs to :otifier instance of this notification.
        # @scope instance
        # @return [Object] Notifier instance of this notification
        belongs_to_composite_xdb_record :notifier, store_with_associated_records: true

        # Mandatory global secondary index to query effectively
        global_secondary_index hash_key: :target_key,     range_key: :created_at, projected_attributes: :all
        global_secondary_index hash_key: :group_owner_id, range_key: :created_at, projected_attributes: :all
        # Optional global secondary index to sort by created_at
        global_secondary_index hash_key: :notifier_key,   range_key: :created_at, projected_attributes: :all
        global_secondary_index hash_key: :notifiable_key, range_key: :created_at, projected_attributes: :all

        validates  :target,     presence: true
        validates  :notifiable, presence: true
        validates  :key,        presence: true

        %i[ all_index! unopened_index opened_index
            filtered_by_association filtered_by_target filtered_by_instance filtered_by_group
            filtered_by_target_type filtered_by_type filtered_by_key filtered_by_options
            latest_order earliest_order latest_order! earliest_order!
            group_owners_only group_members_only unopened_only opened_only! opened_only
            unopened_index_group_members_only opened_index_group_members_only
            within_expiration_only(expiry_delay
            group_members_of_owner_ids_only
            reload
            latest earliest latest! earliest!
            uniq_keys
          ].each do |method|
          # Return a criteria chain in response to a method that will begin or end a chain.
          # For more information, see Dynamoid::Criteria::Chain.
          singleton_class.send(:define_method, method) do |*args, &block|
            # Use scan_index_forward with true as default value to convert Dynamoid::Document into Dynamoid::Criteria::Chain
            # https://github.com/Dynamoid/dynamoid/blob/master/lib/dynamoid/document.rb
            # https://github.com/Dynamoid/dynamoid/blob/master/lib/dynamoid/components.rb
            # https://github.com/Dynamoid/dynamoid/blob/master/lib/dynamoid/criteria.rb
            # https://github.com/Dynamoid/dynamoid/blob/master/lib/dynamoid/criteria/chain.rb
            scan_index_forward(true).send(method, *args, &block)
          end
        end

        %i[ with_target with_notifiable with_group with_group_owner with_group_members with_notifier ].each do |method|
          singleton_class.send(:define_method, method) do |*args, &block|
            self
          end
        end

        # Returns if the notification is group owner.
        # Calls NotificationApi#group_owner? as super method.
        # @return [Boolean] If the notification is group owner
        def group_owner?
          super
        end

        # Raise ActivityNotification::DeleteRestrictionError for notifications.
        # @param [String] error_text Error text for raised exception
        # @raise ActivityNotification::DeleteRestrictionError
        # @return [void]
        def self.raise_delete_restriction_error(error_text)
          raise ActivityNotification::DeleteRestrictionError, error_text
        end

        # Returns prepared notification object to store
        # @return [Object] prepared notification object to store
        # def prepare_to_store
        # end

        protected

          # Returns count of group members of the unopened notification.
          # This method is designed to cache group by query result to avoid N+1 call.
          # @api protected
          # @todo Avoid N+1 call
          #
          # @return [Integer] Count of group members of the unopened notification
          def unopened_group_member_count
            group_members.unopened_only.count
          end

          # Returns count of group members of the opened notification.
          # This method is designed to cache group by query result to avoid N+1 call.
          # @api protected
          # @todo Avoid N+1 call
          #
          # @param [Integer] limit Limit to query for opened notifications
          # @return [Integer] Count of group members of the opened notification
          def opened_group_member_count(limit = ActivityNotification.config.opened_index_limit)
            limit == 0 and return 0
            group_members.opened_only(limit).to_a.length
          end

          # Returns count of group member notifiers of the unopened notification not including group owner notifier.
          # This method is designed to cache group by query result to avoid N+1 call.
          # @api protected
          # @todo Avoid N+1 call
          #
          # @return [Integer] Count of group member notifiers of the unopened notification
          def unopened_group_member_notifier_count
            group_members.unopened_only
                         .filtered_by_association_type("notifier", notifier)
                         .where("notifier_key.ne": notifier_key)
                         .to_a
                         .collect {|n| n.notifier_key }.compact.uniq
                         .length
          end

          # Returns count of group member notifiers of the opened notification not including group owner notifier.
          # This method is designed to cache group by query result to avoid N+1 call.
          # @api protected
          # @todo Avoid N+1 call
          #
          # @param [Integer] limit Limit to query for opened notifications
          # @return [Integer] Count of group member notifiers of the opened notification
          def opened_group_member_notifier_count(limit = ActivityNotification.config.opened_index_limit)
            limit == 0 and return 0
            group_members.opened_only(limit)
                         .filtered_by_association_type("notifier", notifier)
                         .where("notifier_key.ne": notifier_key)
                         .to_a
                         .collect {|n| n.notifier_key }.compact.uniq
                         .length
          end

      end
    end
  end
end
