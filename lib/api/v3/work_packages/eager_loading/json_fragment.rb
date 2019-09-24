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

          class_attribute :links

          class << self
            def link(name, path:, permission: nil, method: :get, type: nil, title: nil, templated: false, payload: payload)
              self.links ||= {}
              links[name] = { path: path,
                              permission: permission,
                              method: method,
                              type: type,
                              title: title,
                              templated: templated,
                              payload: payload }
            end

            def links_select
              admin_checked_links.keys.map { |key| %W('#{key}' action_links.#{key}) }.join(', ')
            end

            def links_href
              admin_checked_links.map do |name, options|
                json = href_json_object(options)
                permission = options[:permission]

                if permission
                  <<-SQL
                  CASE
                  WHEN work_packages.project_id IN (SELECT id FROM #{permission}_projects)
                  THEN #{json}
                  END AS #{name}
                  SQL
                else
                  "#{json} AS #{name}"
                end
              end.join(', ')
            end

            def links_ctes
              admin_checked_links
                .values
                .map { |options| options[:permission] }
                .compact
                .uniq.map do |permission|
                "#{permission}_projects AS (#{::Project.allowed_to(User.current, permission).select(:id).to_sql})"
              end.join(', ')
            end

            protected

            def href_json_object(options)
              method = options[:method]
              type = options[:type]
              title = options[:title]
              templated = options[:templated]
              payload = options[:payload]

              json_params = [["'href'", link_href(options[:path])]]

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

            def link_href(path_options)
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

            def admin_checked_links
              if User.current.admin?
                links
              else
                links.reject { |_, options| options[:permission] == :admin }
              end
            end

            def url_helpers
              @url_helpers ||= OpenProject::StaticRouting::StaticUrlHelpers.new
            end
          end

          link :self,
               path: { api: :work_package, params: %w(id) },
               title: { string: '%s', values: %w(subject) }

          link :schema,
               path: { api: :work_package_schema, params: %w(project_id type_id) }

          link :delete,
               path: { api: :work_package, params: %w(id) },
               permission: :delete_work_packages,
               method: :delete

          link :update,
               path: { api: :work_package_form, params: %w(id) },
               permission: :edit_work_packages,
               method: :post

          link :updateImmediately,
               path: { api: :work_package, params: %w(id) },
               permission: :edit_work_packages,
               method: :patch

          link :copy,
               path: { html: :work_package_path, params: %w(id), queryProps: %w(copy) },
               permission: :add_work_packages,
               type: 'text/html',
               title: { string: 'Copy %s', values: %w(subject) }

          link :logTime,
               path: { html: :new_work_package_time_entry_path, params: %w(id) },
               permission: :log_time,
               type: 'text/html',
               title: { string: 'Log time %s', values: %w(subject) }

          link :move,
               path: { html: :new_work_package_move_path, params: %w(id) },
               permission: :move,
               type: 'text/html',
               title: { string: 'Move %s', values: %w(subject) }

          link :pdf,
               path: { html: :work_package_path, params: %w(id), queryProps: { format: :pdf } },
               permission: :export,
               type: 'application/pdf',
               title: { string: 'Export as PDF' }

          link :atom,
               path: { html: :work_package_path, params: %w(id), queryProps: { format: :atom } },
               permission: :export,
               type: 'application/rss+xml',
               title: { string: 'Atom feed' }

          link :availableRelationCandidates,
               path: { api: :work_package_available_relation_candidates, params: %w(id) },
               title: { string: "Potential work packages to relate to" }

          link :customFields,
               path: { html: :settings_project_path, params: %w(project_id), queryProps: { tab: 'custom_fields' } },
               permission: :edit_project,
               type: 'text/html',
               title: { string: "Custom fields" }

          link :configureForm,
               path: { html: :edit_type_path, params: %w(type_id), queryProps: { tab: 'form_configuration' } },
               permission: :admin,
               type: 'text/html',
               title: { string: "Configure form" }

          link :activities,
               path: { api: :work_package_activities, params: %w(id) }

          link :relations,
               path: { api: :work_package_relations, params: %w(id) }

          link :revisions,
               path: { api: :work_package_revisions, params: %w(id) }

          link :available_watchers,
               path: { api: :available_watchers, params: %w(id) },
               permission: :add_work_package_watchers

          link :watchers,
               path: { api: :work_package_watchers, params: %w(id) },
               permission: :view_work_package_watchers

          link :addRelation,
               path: { api: :work_package_relations, params: %w(id) },
               permission: :manage_work_package_relations,
               method: :post,
               title: { string: "Add relation" }

          link :changeParent,
               path: { api: :work_package, params: %w(id) },
               permission: :manage_subtasks,
               method: :patch,
               title: { string: "Change parent of %s", values: %w(subject) }

          link :addComment,
               path: { api: :work_package_activities, params: %w(id) },
               permission: :add_work_package_notes,
               method: :post,
               title: { string: "Add comment" }

          link :timeEntries,
               path: { html: :work_package_time_entries_path, params: %w(id) },
               permission: :view_time_entries,
               type: 'text/html',
               title: { string: "Time entries" }

          link :addWatcher,
               permission: :add_work_package_watchers,
               path: { api: :work_package_watchers, params: %w(id) },
               method: :post,
               templated: true,
               payload: -> { "json_build_object('_links', json_build_object('user', json_build_object('href', '#{api_v3_paths.user('{user_id}')}')))" }

          link :removeWatcher,
               permission: :delete_work_package_watchers,
               path: -> { "format('#{api_v3_paths.watcher('{user_id}', '%s')}', id)" },
               method: :delete,
               templated: true

          link :previewMarkup,
               method: :post,
               path: -> { "format('#{api_v3_paths.render_markup(link: api_v3_paths.work_package('%s'))}', id)" }

          def json_representer_for(id)
            @json_representers ||= json_representer_map

            @json_representers[id] || '{}'
          end

          def json_representer_map
            sql = <<-SQL
               WITH view_work_packages_projects AS (#{::Project.allowed_to(User.current, :view_work_packages).select(:id).to_sql}),
                    watcher_users AS (SELECT users.*, watchable_id FROM users JOIN watchers ON watchers.watchable_id IN (#{work_packages.map(&:id).join(', ')}) AND watchable_type = 'WorkPackage' AND watchers.user_id = users.id	),
                    #{self.class.links_ctes}

               SELECT
                 work_packages.id,
                 json_build_object('_links',
                   json_strip_nulls(
                     json_build_object('children', COALESCE(children.children, '[]'),
                                       'ancestors', COALESCE(ancestors.ancestors, '[]'),
                                       'parent', COALESCE(parents.parent, json_build_object('href', NULL, 'title', NULL)),
                                       'watch', action_links.watch,
                                       'unwatch', action_links.unwatch,
                                       #{self.class.links_select}
                                      )
                   )
                 )
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
              LEFT OUTER JOIN
              (SELECT id,
                      #{self.class.links_href},
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
