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
        class Hierarchy < Base
          def apply(work_package)
            work_package.visible_children_json = children(work_package.id)
          end

          private

          def children(id)
            @children ||= with_work_package_children

            @children[id] || '[]'
          end

          def with_work_package_children
            sql = <<-SQL
              SELECT id, json_agg(child_hash)
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
              WHERE children.project_id IN (#{::Project.allowed_to(User.current, :view_work_packages).select(:id).to_sql})
              AND relations.from_id IN (#{Array(work_packages.map(&:id)).join(', ')})
              ) children_by_id
              GROUP BY id
            SQL

            ActiveRecord::Base.connection.select_all(sql).to_a.map(&:values).to_h
          end
        end
      end
    end
  end
end
