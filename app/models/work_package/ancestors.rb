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

module WorkPackage::Ancestors
  extend ActiveSupport::Concern

  included do
    attr_accessor :work_package_ancestors

    ##
    # Retrieve stored eager loaded ancestors
    # or use awesome_nested_set#ancestors reduced by visibility
    def visible_ancestors(user)
      if work_package_ancestors.nil?
        self.class.aggregate_ancestors(id, user)[id]
      else
        work_package_ancestors
      end
    end
  end

  class_methods do
    def aggregate_ancestors(work_package_ids, user)
      ::WorkPackage::Ancestors::Aggregator.new(work_package_ids, user).results
    end
  end

  ##
  # Aggregate ancestor data for the given work package IDs.
  # Ancestors visible to the given user are returned, grouped by each input ID.
  class Aggregator
    attr_accessor :user, :ids

    def initialize(work_package_ids, user)
      @user = user
      @ids = work_package_ids
    end

    def results
      default = Hash.new do |hash, id|
        hash[id] = '[]'
      end

      default.merge(with_work_package_ancestors)
    end

    private

    def with_work_package_ancestors
      sql = <<-SQL
        SELECT id, json_agg(ancestor_hash)
        FROM
        (
        SELECT relations.to_id AS id, json_build_object('href', '/api/v3/work_packages/' || ancestors.id,
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
        WHERE ancestors.project_id IN (#{Project.allowed_to(User.current, :view_work_packages).select(:id).to_sql})
        AND relations.to_id IN (#{Array(@ids).join(', ')})
        ORDER BY hierarchy DESC
        ) ancestors_by_id
        GROUP BY id
      SQL

      ActiveRecord::Base.connection.select_all(sql).to_a.map(&:values).to_h
    end
  end
end
