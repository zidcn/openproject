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
          def apply(work_package)
            work_package.json_representer_fragment = json_representer_for(work_package.id)
          end

          private

          def json_representer_for(id)
            @json_representers ||= json_representer_map

            @json_representers[id] || '{}'
          end

          def json_representer_map
            sql = <<-SQL
               WITH view_work_packages_projects AS (#{::Project.allowed_to(User.current, :view_work_packages).select(:id).to_sql}),
                    edit_work_packages_projects AS (#{::Project.allowed_to(User.current, :edit_work_packages).select(:id).to_sql})

               SELECT
                 work_packages.id,
                 json_build_object('_links',
                   json_strip_nulls(
                     json_build_object('children', COALESCE(children.children, '[]'),
                                       'ancestors', COALESCE(ancestors.ancestors, '[]'),
                                       'updateImmediately', action_links.update_immediately,
                                       'update', action_links.update
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
                               json_build_object('href', '/api/v3/work_packages/' || children.id,
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
                             json_build_object('href', '/api/v3/work_packages/' || ancestors.id,
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
                      GROUP BY id) ancestors on children.id = ancestors.id
              LEFT OUTER JOIN
              (SELECT id,
                      CASE
                      WHEN work_packages.project_id IN (SELECT id FROM edit_work_packages_projects)
                        THEN json_build_object('href', '/api/v3/work_packages/' || id, 'method', 'patch')
                      END  AS update_immediately,
                      CASE
                      WHEN work_packages.project_id IN (SELECT id FROM edit_work_packages_projects)
                        THEN json_build_object('href', '/api/v3/work_packages/' || id || '/form', 'method', 'post')
                      END AS update
                      FROM work_packages
                      WHERE id IN (#{work_packages.map(&:id).join(', ')})
              ) action_links ON action_links.id = work_packages.id
              WHERE work_packages.id IN (#{work_packages.map(&:id).join(', ')})
            SQL

            ActiveRecord::Base.connection.select_all(sql).to_a.map(&:values).to_h
          end
        end
      end
    end
  end
end
