#-- encoding: UTF-8

#-- copyright
# OpenProject is a project management system.
# Copyright (C) 2012-2018 the OpenProject Foundation (OPF)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2017 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See docs/COPYRIGHT.rdoc for more details.
#++

module API
  module V3
    module WorkPackages
      class WorkPackageRepresenter < ::API::Decorators::Single
        include API::Decorators::LinkedResource
        include API::Decorators::DateProperty
        include API::Decorators::FormattableProperty
        prepend API::Decorators::JsonFragmentRepresenter
        include API::Caching::CachedRepresenter
        include ::API::V3::Attachments::AttachableRepresenterMixin
        extend ::API::V3::Utilities::CustomFieldInjector::RepresenterClass

        cached_representer key_parts: %i(project),
                           disabled: false

        def initialize(model, current_user:, embed_links: false)
          model = load_complete_model(model)

          super
        end

        self_link title_getter: ->(*) { represented.subject }

        link :addChild,
             cache_if: -> { current_user_allowed_to(:add_work_packages, context: represented.project) } do
          next if represented.milestone? || represented.new_record?

          {
            href: api_v3_paths.work_packages_by_project(represented.project.identifier),
            method: :post,
            title: "Add child of #{represented.subject}"
          }
        end

        property :id,
                 render_nil: true

        property :lock_version,
                 render_nil: true,
                 getter: ->(*) {
                   lock_version.to_i
                 }

        property :subject,
                 render_nil: true

        formattable_property :description

        date_property :start_date,
                      skip_render: ->(represented:, **) {
                        represented.milestone?
                      }

        date_property :due_date,
                      skip_render: ->(represented:, **) {
                        represented.milestone?
                      }

        # Using setter: does not work in case the provided date fragment is nil.
        date_property :date,
                      getter: default_date_getter(:due_date),
                      setter: ->(*) {
                        # handled in reader
                      },
                      reader: ->(decorator:, doc:, **) {
                        next unless doc.key?('date')

                        date = decorator
                               .datetime_formatter
                               .parse_date(doc['date'],
                                           name.to_s.camelize(:lower),
                                           allow_nil: true)

                        self.due_date = self.start_date = date
                      },
                      skip_render: ->(represented:, **) {
                        !represented.milestone?
                      }

        property :estimated_time,
                 exec_context: :decorator,
                 getter: ->(*) do
                   datetime_formatter.format_duration_from_hours(represented.estimated_hours,
                                                                 allow_nil: true)
                 end,
                 render_nil: true

        property :derived_estimated_time,
                 exec_context: :decorator,
                 getter: ->(*) do
                   datetime_formatter.format_duration_from_hours(represented.derived_estimated_hours,
                                                                 allow_nil: true)
                 end,
                 render_nil: true

        property :spent_time,
                 exec_context: :decorator,
                 getter: ->(*) do
                   datetime_formatter.format_duration_from_hours(represented.spent_hours)
                 end,
                 if: ->(*) {
                   view_time_entries_allowed?
                 },
                 uncacheable: true

        property :done_ratio,
                 as: :percentageDone,
                 render_nil: true,
                 if: ->(*) { Setting.work_package_done_ratio != 'disabled' }

        date_time_property :created_at

        date_time_property :updated_at

        property :watchers,
                 embedded: true,
                 exec_context: :decorator,
                 uncacheable: true,
                 if: ->(*) {
                   current_user_allowed_to(:view_work_package_watchers,
                                           context: represented.project) &&
                     embed_links
                 }

        property :relations,
                 embedded: true,
                 exec_context: :decorator,
                 if: ->(*) { embed_links },
                 uncacheable: true

        associated_resource :category

        associated_resource :type

        associated_resource :priority

        associated_resource :project

        associated_resource :status

        associated_resource :author,
                            v3_path: :user,
                            representer: ::API::V3::Users::UserRepresenter

        associated_resource :responsible,
                            getter: ::API::V3::Principals::AssociatedSubclassLambda.getter(:responsible),
                            setter: PrincipalSetter.lambda(:responsible),
                            link: ::API::V3::Principals::AssociatedSubclassLambda.link(:responsible)

        associated_resource :assignee,
                            getter: ::API::V3::Principals::AssociatedSubclassLambda.getter(:assigned_to),
                            setter: PrincipalSetter.lambda(:assigned_to, :assignee),
                            link: ::API::V3::Principals::AssociatedSubclassLambda.link(:assigned_to)

        associated_resource :fixed_version,
                            as: :version,
                            v3_path: :version,
                            representer: ::API::V3::Versions::VersionRepresenter

        associated_resource :parent,
                            v3_path: :work_package,
                            representer: ::API::V3::WorkPackages::WorkPackageRepresenter,
                            skip_render: ->(*) { represented.parent && !represented.parent.visible? },
                            skip_link: true,
                            link: ->(*) {
                              if represented.parent&.visible?
                                {
                                  href: api_v3_paths.work_package(represented.parent.id),
                                  title: represented.parent.subject
                                }
                              else
                                {
                                  href: nil,
                                  title: nil
                                }
                              end
                            },
                            setter: ->(fragment:, **) do
                              next if fragment.empty?

                              href = fragment['href']

                              new_parent = if href
                                             id = ::API::Utilities::ResourceLinkParser
                                                  .parse_id href,
                                                            property: 'parent',
                                                            expected_version: '3',
                                                            expected_namespace: 'work_packages'

                                             WorkPackage.find_by(id: id) ||
                                               ::WorkPackage::InexistentWorkPackage.new(id: id)
                                           end

                              represented.parent = new_parent
                            end

        resources :customActions,
                  uncacheable_link: true,
                  link: ->(*) {
                    ordered_custom_actions.map do |action|
                      {
                        href: api_v3_paths.custom_action(action.id),
                        title: action.name
                      }
                    end
                  },
                  getter: ->(*) {
                    ordered_custom_actions.map do |action|
                      ::API::V3::CustomActions::CustomActionRepresenter.new(action, current_user: current_user)
                    end
                  },
                  setter: ->(*) do
                    # noop
                  end

        def _type
          'WorkPackage'
        end

        def to_hash(*args)
          # Define all accessors on the customizable as they
          # will be used afterwards anyway. Otherwise, we will have to
          # go through method_missing which will take more time.
          represented.define_all_custom_field_accessors

          super
        end

        def watchers
          # TODO/LEGACY: why do we need to ensure a specific order here?
          watchers = represented.watcher_users.order(User::USER_FORMATS_STRUCTURE[Setting.user_format])
          self_link = api_v3_paths.work_package_watchers(represented.id)

          Users::UserCollectionRepresenter.new(watchers,
                                               self_link,
                                               current_user: current_user)
        end

        def current_user_watcher?
          represented.watchers.any? { |w| w.user_id == current_user.id }
        end

        def current_user_update_allowed?
          current_user_allowed_to(:edit_work_packages, context: represented.project) ||
            current_user_allowed_to(:assign_versions, context: represented.project)
        end

        def relations
          self_path = api_v3_paths.work_package_relations(represented.id)
          visible_relations = represented
                              .visible_relations(current_user)
                              .non_hierarchy
                              .includes(::API::V3::Relations::RelationCollectionRepresenter.to_eager_load)

          ::API::V3::Relations::RelationCollectionRepresenter.new(visible_relations,
                                                                  self_path,
                                                                  current_user: current_user)
        end

        def estimated_time=(value)
          represented.estimated_hours = datetime_formatter.parse_duration_to_hours(value,
                                                                                   'estimatedTime',
                                                                                   allow_nil: true)
        end

        def derived_estimated_time=(value)
          represented.derived_estimated_hours = datetime_formatter
            .parse_duration_to_hours(value, 'derivedEstimatedTime', allow_nil: true)
        end

        def spent_time=(value)
          # noop
        end

        def ordered_custom_actions
          # As the custom actions are sometimes set as an array
          represented.custom_actions(current_user).to_a.sort_by(&:position)
        end

        self.to_eager_load = %i[type
                                watchers]

        # The dynamic class generation introduced because of the custom fields interferes with
        # the class naming as well as prevents calls to super
        def json_cache_key
          ['API',
           'V3',
           'WorkPackages',
           'WorkPackageRepresenter',
           'json',
           I18n.locale,
           json_key_representer_parts,
           represented.cache_checksum,
           Setting.work_package_done_ratio,
           Setting.feeds_enabled?]
        end

        def view_time_entries_allowed?
          current_user_allowed_to(:view_time_entries, context: represented.project)
        end

        def load_complete_model(model)
          ::API::V3::WorkPackages::WorkPackageEagerLoadingWrapper.wrap_one(model, current_user)
        end
      end
    end
  end
end
