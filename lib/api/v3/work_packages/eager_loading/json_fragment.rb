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
      module EagerLoading
        class JsonFragment < Base
          extend ::API::V3::Utilities::PathHelper
          include ::API::V3::Utilities::PathHelper

          def apply(work_package)
            work_package.json_representer_fragment = json_representer_for(work_package.id)
          end

          class_attribute :action_links,
                          :association_links,
                          :properties

          class << self
            # TODO: turn action link into separate class so that
            # instances can be generated here
            def action_link(name, path:, permission: nil, method: :get, type: nil, title: nil, templated: false, payload: payload, condition: nil)
              self.action_links ||= {}
              action_links[name] = { path: path,
                                     permission: permission,
                                     method: method,
                                     type: type,
                                     title: title,
                                     templated: templated,
                                     payload: payload,
                                     condition: nil }
            end

            # TODO: turn proerty link into separate class so that
            # instances can be generated here
            def association_link(name, as: name, path: nil, join:, title: nil, href: nil)
              self.association_links ||= {}

              association_links[name] = { as: as,
                                          path: path,
                                          join: join,
                                          title: title,
                                          href: href }
            end

            def association_links_joins
              association_links
                .map do |name, link|
                  if link[:join].is_a?(Symbol)
                    "LEFT OUTER JOIN #{link[:join]} #{name} ON #{name}.id = work_packages.#{name}_id"
                  else
                    "LEFT OUTER JOIN #{link[:join][:table]} #{name} ON #{link[:join][:condition]} AND #{name}.id = work_packages.#{name}_id"
                  end
                end
                .join(' ')
            end

            def association_links_selects
              association_links
                .map do |name, link|
                  path_name = link[:path] ? link[:path][:api] : name
                  title = link[:title] ? link[:title].call : "#{name}.name"

                  href = link[:href] ? link[:href].call : "format('#{api_v3_paths.send(path_name, '%s')}', #{name}.id)"

                  <<-SQL
                  '#{link[:as]}', CASE
                                  WHEN #{name}.id IS NOT NULL
                                  THEN
                                  json_build_object('href', #{href},
                                                    'title', #{title})
                                  ELSE
                                  json_build_object('href', NULL,
                                                    'title', NULL)
                                  END
                  SQL
                end
                .join(', ')
            end

            def property(name,
                         column: name,
                         representation: nil,
                         render_if: nil)
              self.properties ||= {}

              properties[name] = { column: column, render_if: render_if, representation: representation }
            end

            def action_links_select
              admin_checked_action_links.keys.map { |key| %W('#{key}' action_links.#{key}) }.join(', ')
            end

            def action_links_href
              admin_checked_action_links.map do |name, options|
                json = href_json_object(options)
                permission = options[:permission]
                condition = if options[:condition]
                              "#{options[:condition]} AND "
                            else
                              ""
                            end

                if permission
                  <<-SQL
                  CASE
                  WHEN #{condition} work_packages.project_id IN (SELECT id FROM #{permission}_projects)
                  THEN #{json}
                  END AS #{name}
                  SQL
                else
                  "#{json} AS #{name}"
                end
              end.join(', ')
            end

            #def action_links_ctes
            #  admin_checked_action_links
            #    .values
            #    .map { |options| options[:permission] }
            #end

            def all_ctes
              permissions = admin_checked_action_links
                            .values
                            .map { |options| options[:permission] }

              # for spent time
              permissions << :view_time_entries

              permissions
                .compact
                .uniq
                .map do |permission|
                  "#{permission}_projects AS (#{::Project.allowed_to(User.current, permission).select(:id).to_sql})"
                end
                .join(', ')
            end

            protected

            def href_json_object(options)
              method = options[:method]
              type = options[:type]
              title = options[:title]
              templated = options[:templated]
              payload = options[:payload]

              json_params = [["'href'", action_link_href(options[:path])]]

              if method != :get
                json_params << %W('method' '#{method.to_s}')
              end

              if type
                json_params << %W('type' '#{type.to_s}')
              end

              if title
                json_params << ["'title'", link_title(title)]
              end

              if templated
                json_params << ["'templated'", 'true']
              end

              if payload
                json_params << ["'payload'", payload.call]
              end

              "json_build_object(#{json_params.join(', ')})"
            end

            def action_link_href(path_options)
              if path_options.respond_to?(:call)
                custom_link_href(path_options)
              else
                static_link_href(path_options)
              end
            end

            def static_link_href(path_options)
              path_params = path_options[:params]

              sql_path = if path_options[:api]
                           api_v3_paths.send(path_options[:api], *path_params.map { |_| '%s' })
                         elsif path_options[:html]
                           url_helpers.send(path_options[:html], *path_params.map { |_| '%s' }, path_options[:queryProps]).gsub(/%25s/, '%s')
                         end

              "format('#{sql_path}', #{path_params.join(', ')})"
            end

            def custom_link_href(path_options)
              path_options.call
            end

            def link_title(title_options)
              if title_options[:values]
                "format('#{title_options[:string]}', #{title_options[:values].join(', ')})"
              else
                "'#{title_options[:string]}'"
              end
            end

            def admin_checked_action_links
              if User.current.admin?
                action_links
              else
                action_links.reject { |_, options| options[:permission] == :admin }
              end
            end

            def url_helpers
              @url_helpers ||= OpenProject::StaticRouting::StaticUrlHelpers.new
            end

            public

            # Properties
            # TODO: extract into class
            def properties_sql
              properties.map do |name, options|
                representation = if options[:representation]
                                   options[:representation].call
                                 else
                                   "work_packages.#{options[:column]}"
                                 end

                "'#{name}', #{representation}"
              end.join(', ')
            end

            def properties_conditions
              properties
                .select { |_, options| options[:render_if] }
                .map do |name, options|
                "- CASE WHEN #{options[:render_if].call} THEN '' ELSE '#{name}' END"
              end.join(' ')
            end
          end

          property :id

          property :lockVersion,
                   column: :lock_version

          property :subject

          property :startDate,
                   column: :start_date,
                   render_if: -> { "type.is_milestone = '#{OpenProject::Database::DB_VALUE_FALSE}'" }

          property :dueDate,
                   column: :due_date,
                   render_if: -> { "type.is_milestone = '#{OpenProject::Database::DB_VALUE_FALSE}'" }

          property :date,
                   column: :due_date,
                   render_if: -> { "type.is_milestone = '#{OpenProject::Database::DB_VALUE_TRUE}'" }

          property :createdAt,
                   column: :created_at

          property :updatedAt,
                   column: :updated_at

          property :percentageDone,
                   column: :done_ratio,
                   render_if: -> { Setting.work_package_done_ratio != 'disabled' ? "1 = 1" : "1 = 0" }

          property :estimatedTime,
                   representation: -> { "make_interval(mins := CAST(work_packages.estimated_hours * 60 as int))" }

          property :derivedEstimatedTime,
                   representation: -> { "make_interval(mins := CAST(work_packages.derived_estimated_hours * 60 as int))" }

          property :spentTime,
                   representation: -> { "make_interval(mins := CAST(spent_time.hours * 60 as int))" },
                   render_if: -> { "work_packages.project_id IN (SELECT id FROM view_time_entries_projects)"}

          action_link :self,
                      path: { api: :work_package, params: %w(id) },
                      title: { string: '%s', values: %w(subject) }

          action_link :schema,
                      path: { api: :work_package_schema, params: %w(project_id type_id) }

          action_link :delete,
                      path: { api: :work_package, params: %w(id) },
                      permission: :delete_work_packages,
                      method: :delete

          action_link :update,
                      path: { api: :work_package_form, params: %w(id) },
                      permission: :edit_work_packages,
                      method: :post

          action_link :updateImmediately,
                      path: { api: :work_package, params: %w(id) },
                      permission: :edit_work_packages,
                      method: :patch

          action_link :copy,
                      path: { html: :work_package_path, params: %w(id), queryProps: %w(copy) },
                      permission: :add_work_packages,
                      type: 'text/html',
                      title: { string: 'Copy %s', values: %w(subject) }

          action_link :logTime,
                      path: { html: :new_work_package_time_entry_path, params: %w(id) },
                      permission: :log_time,
                      type: 'text/html',
                      title: { string: 'Log time %s', values: %w(subject) }

          action_link :move,
                      path: { html: :new_work_package_move_path, params: %w(id) },
                      permission: :move,
                      type: 'text/html',
                      title: { string: 'Move %s', values: %w(subject) }

          action_link :pdf,
                      path: { html: :work_package_path, params: %w(id), queryProps: { format: :pdf } },
                      permission: :export,
                      type: 'application/pdf',
                      title: { string: 'Export as PDF' }

          action_link :atom,
                      path: { html: :work_package_path, params: %w(id), queryProps: { format: :atom } },
                      permission: :export,
                      type: 'application/rss+xml',
                      title: { string: 'Atom feed' }

          action_link :availableRelationCandidates,
                      path: { api: :work_package_available_relation_candidates, params: %w(id) },
                      title: { string: "Potential work packages to relate to" }

          action_link :customFields,
                      path: { html: :settings_project_path, params: %w(project_id), queryProps: { tab: 'custom_fields' } },
                      permission: :edit_project,
                      type: 'text/html',
                      title: { string: "Custom fields" }

          action_link :configureForm,
                      path: { html: :edit_type_path, params: %w(type_id), queryProps: { tab: 'form_configuration' } },
                      permission: :admin,
                      type: 'text/html',
                      title: { string: "Configure form" }

          action_link :activities,
                      path: { api: :work_package_activities, params: %w(id) }

          action_link :relations,
                      path: { api: :work_package_relations, params: %w(id) }

          action_link :revisions,
                      path: { api: :work_package_revisions, params: %w(id) }

          action_link :availableWatchers,
                      path: { api: :available_watchers, params: %w(id) },
                      permission: :add_work_package_watchers

          action_link :watchers,
                      path: { api: :work_package_watchers, params: %w(id) },
                      permission: :view_work_package_watchers

          action_link :addRelation,
                      path: { api: :work_package_relations, params: %w(id) },
                      permission: :manage_work_package_relations,
                      method: :post,
                      title: { string: "Add relation" }

          action_link :changeParent,
                      path: { api: :work_package, params: %w(id) },
                      permission: :manage_subtasks,
                      method: :patch,
                      title: { string: "Change parent of %s", values: %w(subject) }

          action_link :addChild,
                      path: { api: :work_packages_by_project, params: %w(project_id) },
                      permission: :add_work_packages,
                      method: :post,
                      title: { string: "Add child of %s", values: %w(subject) },
                      condition: "type_id IN (SELECT id from types WHERE is_milestone = '#{OpenProject::Database::DB_VALUE_FALSE})'"

          action_link :addComment,
                      path: { api: :work_package_activities, params: %w(id) },
                      permission: :add_work_package_notes,
                      method: :post,
                      title: { string: "Add comment" }

          action_link :timeEntries,
                      path: { html: :work_package_time_entries_path, params: %w(id) },
                      permission: :view_time_entries,
                      type: 'text/html',
                      title: { string: "Time entries" }

          action_link :addWatcher,
                      permission: :add_work_package_watchers,
                      path: { api: :work_package_watchers, params: %w(id) },
                      method: :post,
                      templated: true,
                      payload: -> { "json_build_object('_links', json_build_object('user', json_build_object('href', '#{api_v3_paths.user('{user_id}')}')))" }

          action_link :removeWatcher,
                      permission: :delete_work_package_watchers,
                      path: -> { "format('#{api_v3_paths.watcher('{user_id}', '%s')}', id)" },
                      method: :delete,
                      templated: true

          action_link :previewMarkup,
                      method: :post,
                      path: -> { "format('#{api_v3_paths.render_markup(link: api_v3_paths.work_package('%s'))}', id)" }

          action_link :addAttachment,
                      permission: :edit_work_packages,
                      method: :post,
                      path: { api: :attachments_by_work_package, params: %w(id) }

          action_link :attachments,
                      path: { api: :attachments_by_work_package, params: %w(id) }

          association_link :type,
                           path: { api: :type, params: %w(type_id) },
                           join: :types

          association_link :category,
                           path: { api: :category, params: %w(category_id) },
                           join: :categories

          association_link :project,
                           path: { api: :project, params: %w(project_id) },
                           join: :projects

          association_link :status,
                           path: { api: :status, params: %w(status_id) },
                           join: :statuses

          association_link :priority,
                           path: { api: :priority, params: %w(priority_id) },
                           join: { table: :enumerations, condition: "priority.type = 'IssuePriority'" }

          association_link :author,
                           path: { api: :user, params: %w(author_id) },
                           join: :users,
                           title: -> {
                             join_string = if Setting.user_format == :lastname_coma_firstname
                                             " || ', ' || "
                                           else
                                             " || ' ' || "
                                           end

                             User::USER_FORMATS_STRUCTURE[Setting.user_format].map { |p| "author.#{p}" }.join(join_string)
                           }

          association_link :responsible,
                           path: { api: :user, params: %w(responsible_id) },
                           join: :users,
                           title: -> {
                             join_string = if Setting.user_format == :lastname_coma_firstname
                                             " || ', ' || "
                                           else
                                             " || ' ' || "
                                           end

                             User::USER_FORMATS_STRUCTURE[Setting.user_format].map { |p| "responsible.#{p}" }.join(join_string)
                           },
                           href: -> {
                             <<-SQL
                              CASE
                              WHEN responsible.type = 'User'
                              THEN format('#{api_v3_paths.user('%s')}', responsible_id)
                              ELSE format('#{api_v3_paths.group('%s')}', responsible_id)
                              END
                             SQL
                           }

          association_link :assigned_to,
                           as: :assignee,
                           path: { api: :user, params: %w(assigned_to_id) },
                           join: :users,
                           title: -> {
                             join_string = if Setting.user_format == :lastname_coma_firstname
                                             " || ', ' || "
                                           else
                                             " || ' ' || "
                                           end

                             User::USER_FORMATS_STRUCTURE[Setting.user_format].map { |p| "assigned_to.#{p}" }.join(join_string)
                           },
                           href: -> {
                             <<-SQL
                              CASE
                              WHEN assigned_to.type = 'User'
                              THEN format('#{api_v3_paths.user('%s')}', assigned_to.id)
                              ELSE format('#{api_v3_paths.group('%s')}', assigned_to.id)
                              END
                             SQL
                           }

          association_link :fixed_version,
                           as: :version,
                           path: { api: :version, params: %w(fixed_version_id) },
                           join: :versions

          def json_representer_for(id)
            @json_representers ||= json_representer_map

            @json_representers[id] || '{}'
          end

          def json_representer_map
            ActiveRecord::Base.connection.execute("SET intervalstyle = 'iso_8601';")

            sql = <<-SQL
               WITH view_work_packages_projects AS (#{::Project.allowed_to(User.current, :view_work_packages).select(:id).to_sql}),
                    watcher_users AS (SELECT users.*, watchable_id FROM users JOIN watchers ON watchers.watchable_id IN (#{work_packages.map(&:id).join(', ')}) AND watchable_type = 'WorkPackage' AND watchers.user_id = users.id	),
                    #{self.class.all_ctes}

               SELECT
                 work_packages.id,
                 json_build_object(
                   #{self.class.properties_sql},
                   '_links', json_strip_nulls(
                     json_build_object('children', COALESCE(children.children, '[]'),
                                       'ancestors', COALESCE(ancestors.ancestors, '[]'),
                                       'parent', COALESCE(parents.parent, json_build_object('href', NULL, 'title', NULL)),
                                       #{self.class.association_links_selects},
                                       'watch', action_links.watch,
                                       'unwatch', action_links.unwatch,
                                       #{self.class.action_links_select},
                                       'customActions', COALESCE(custom_actions.href, '[]')
                                      )
                   )
                 )::jsonb #{self.class.properties_conditions}
               FROM
                 work_packages
               LEFT OUTER JOIN
               (SELECT id, json_agg(child_hash) as children
                            FROM
                            (
                            SELECT
                               relations.from_id AS id,
                               json_build_object('href', format('#{api_v3_paths.work_package('%s')}', children.id),
                                                 'title', children.subject) AS child_hash
                            FROM relations
                            JOIN work_packages children ON
                              children.id = relations.to_id
                              AND relations.hierarchy = 1
                              AND relations.blocks = 0
                              AND relations.follows = 0
                              AND relations.relates = 0
                              AND relations.includes = 0
                              AND relations.duplicates = 0
                              AND relations.requires = 0
                            WHERE children.project_id IN (SELECT id from view_work_packages_projects)
                            AND relations.from_id IN (#{work_packages.map(&:id).join(', ')})
                            ) children_by_id
                            GROUP BY id) children ON children.id = work_packages.id
              LEFT OUTER JOIN
              (SELECT id, json_agg(ancestor_hash) as ancestors
                      FROM
                      (
                      SELECT relations.to_id AS id,
                             json_build_object('href', format('#{api_v3_paths.work_package('%s')}', ancestors.id),
                                               'title', ancestors.subject) AS ancestor_hash
                      FROM relations
                      JOIN work_packages ancestors ON
                        ancestors.id = relations.from_id
                        AND relations.hierarchy > 0
                        AND relations.blocks = 0
                        AND relations.follows = 0
                        AND relations.relates = 0
                        AND relations.includes = 0
                        AND relations.duplicates = 0
                        AND relations.requires = 0
                      WHERE ancestors.project_id IN (SELECT id FROM view_work_packages_projects)
                      AND relations.to_id IN (#{work_packages.map(&:id).join(', ')})
                      ORDER BY hierarchy DESC
                      ) ancestors_by_id
                      GROUP BY id) ancestors on work_packages.id = ancestors.id
              LEFT OUTER JOIN
              ( SELECT relations.to_id AS id,
                             json_build_object('href', format('#{api_v3_paths.work_package('%s')}', parents.id),
                                               'title', parents.subject) AS parent
                      FROM relations
                      JOIN work_packages parents ON
                        parents.id = relations.from_id
                        AND relations.hierarchy = 1
                        AND relations.blocks = 0
                        AND relations.follows = 0
                        AND relations.relates = 0
                        AND relations.includes = 0
                        AND relations.duplicates = 0
                        AND relations.requires = 0
                        AND parents.project_id IN (SELECT id FROM view_work_packages_projects)
                        AND relations.to_id IN (#{work_packages.map(&:id).join(', ')})
                      ORDER BY hierarchy DESC
                      ) parents on work_packages.id = parents.id
              #{self.class.association_links_joins}
              LEFT OUTER JOIN
              (SELECT id,
                      #{self.class.action_links_href},
                      CASE
                      WHEN #{User.current.id} NOT IN (SELECT id FROM watcher_users WHERE watchable_id = work_packages.id)
                        THEN json_build_object('href', '/api/v3/work_packages/' || id || '/watchers',
                                               'method', 'post',
                                               'payload', json_build_object('_links', json_build_object('user', json_build_object('href', '/api/v3/users/#{User.current.id}'))))
                      END AS watch,
                      CASE
                      WHEN #{User.current.id} IN (SELECT id FROM watcher_users WHERE watchable_id = work_packages.id)
                        THEN json_build_object('href', '/api/v3/work_packages/' || id || '/watchers/' || #{User.current.id},
                                               'method', 'delete')
                      END AS unwatch
                      FROM work_packages
                      WHERE id IN (#{work_packages.map(&:id).join(', ')})
              ) action_links ON action_links.id = work_packages.id
              LEFT OUTER JOIN
              (
                SELECT id, json_agg(href) AS href
                FROM (
                SELECT work_packages.id, json_build_object('href', format('#{api_v3_paths.custom_action('%s')}', custom_actions.id), 
                                                           'title', custom_actions.name) href
                FROM custom_actions
                LEFT OUTER JOIN
                  custom_actions_projects
                  ON custom_actions_projects.custom_action_id = custom_actions.id
                LEFT OUTER JOIN
                  custom_actions_roles
                  ON custom_actions_roles.custom_action_id = custom_actions.id
                LEFT OUTER JOIN
                  members ON custom_actions_projects.project_id = members.project_id AND members.user_id = #{User.current.id}
                LEFT OUTER JOIN
                  member_roles ON member_roles.member_id = members.id
                LEFT OUTER JOIN
                  custom_actions_statuses
                  ON custom_actions_statuses.custom_action_id = custom_actions.id
                LEFT OUTER JOIN
                  custom_actions_types
                  ON custom_actions_types.custom_action_id = custom_actions.id
                LEFT OUTER JOIN
                  work_packages ON (work_packages.project_id = custom_actions_projects.project_id OR custom_actions_projects.project_id IS NULL)
                    AND (work_packages.type_id = custom_actions_types.type_id OR custom_actions_types.type_id IS NULL)
                  AND (work_packages.type_id = custom_actions_statuses.status_id OR custom_actions_statuses.status_id IS NULL)
                  AND (member_roles.role_id = custom_actions_roles.role_id OR custom_actions_roles.role_id IS NULL)
                  AND work_packages.id IN (#{work_packages.map(&:id).join(', ')})
                ORDER BY custom_actions.position ASC ) custom_actions
                GROUP BY custom_actions.id
              ) custom_actions on custom_actions.id = work_packages.id
              LEFT OUTER JOIN
              (
                #{API::V3::WorkPackages::WorkPackageEagerLoadingWrapper.add_eager_loading(WorkPackage.where(id: work_packages.map(&:id)), User.current).except(:select).select(:id, 'spent_time_hours.hours').to_sql}
              ) spent_time ON spent_time.id = work_packages.id
              WHERE work_packages.id IN (#{work_packages.map(&:id).join(', ')})
            SQL

            ActiveRecord::Base.connection.select_all(sql).to_a.map(&:values).to_h
          end

          def url_helpers
            @url_helpers ||= OpenProject::StaticRouting::StaticUrlHelpers.new
          end
        end
      end
    end
  end
end
