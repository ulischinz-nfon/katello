module Katello
  class DockerMetaTag < Katello::Model
    include ScopedSearchExtensions

    belongs_to :repository, :inverse_of => :docker_meta_tags, :class_name => "Katello::Repository"

    belongs_to :schema1, :class_name => "Katello::DockerTag",
                          :inverse_of => :schema1_meta_tag

    belongs_to :schema2, :class_name => "Katello::DockerTag",
                          :inverse_of => :schema2_meta_tag

    scoped_search :on => :name, :complete_value => true, :rename => :tag
    scoped_search :on => :id, :only_explicit => true
    scoped_search :on => :name, :complete_value => true
    scoped_search :on => :schema_version, :rename => :schema_version, :complete_value => { "1" => "1", "2" => "2"},
                  :only_explicit => true, :ext_method => :find_by_schema_version, :operators => ["="]
    scoped_search :relation => :repository, :on => :container_repository_name, :rename => :image,
                  :complete_value => true, :only_explicit => true
    scoped_search :on => :digest, :rename => :digest, :complete_value => false,
                  :only_explicit => true, :ext_method => :find_by_digest, :operators => ["="]
    scoped_search :relation => :repositories, :on => :name, :rename => :repository, :complete_value => true,
                  :ext_method => :search_by_repo_name, :only_explicit => true

    def self.search_by_repo_name(_key, operator, value)
      conditions = sanitize_sql_for_conditions(["#{Katello::RootRepository.table_name}.name #{operator} ?", value_to_sql(operator, value)])
      query = self.joins(:repository => :root).where(conditions).select('id')
      {:conditions => "#{self.table_name}.id IN (#{query.to_sql})"}
    end

    def self.meta_tags_by_digest_query(operator, digest, manifest_klass)
      search = "digest #{operator} ?"
      query = DockerMetaTag.search_in_tags(DockerTag.where(:docker_taggable_type => manifest_klass.name,
                                                           :docker_taggable_id => manifest_klass.where(search, digest))).select(:id).to_sql
      "#{DockerMetaTag.table_name}.id in (#{query})"
    end

    def self.find_by_digest(_key, operator, value)
      if operator == '='
        conditions = meta_tags_by_digest_query(operator, value, DockerManifest) + " OR " + meta_tags_by_digest_query(operator, value, DockerManifestList)
      else
        #failure condition. No such value so must return 0
        conditions = "1=0"
      end
      { :conditions => conditions }
    end

    def self.find_by_schema_version(_key, operator, value)
      conditions = ""
      if operator == '='
        if ["1", "2"].include?(value)
          column = if value == "1"
                     "schema1_id"
                   else
                     "schema2_id"
                   end
          docker_meta_tag_arel_table = ::Katello::DockerMetaTag.arel_table
          conditions = docker_meta_tag_arel_table[column].not_eq(nil).to_sql
        else
          #failure condition. No such value so must return 0
          conditions = "1=0"
        end
      end
      { :conditions => conditions }
    end

    def self.delegate_to_tags(*names)
      names.each do |name|
        define_method(name) do
          if schema2
            schema2.send(name)
          else
            schema1.send(name)
          end
        end
      end
    end

    delegate_to_tags :docker_manifest
    delegate_to_tags :product, :environment, :content_view_version

    def repositories
      [self.repository]
    end

    def related_tags
      self.class.where(:repository_id => repository.group, :name => name)
    end

    def self.in_repositories(repos, grouped = false)
      if grouped
        search_in_tags(DockerTag.in_repositories(repos).grouped)
      else
        search_in_tags(DockerTag.in_repositories(repos))
      end
    end

    def self.search_in_tags(tags)
      sql = tags.select("#{::Katello::DockerTag.table_name}.id").to_sql
      self.where("#{self.table_name}.schema1_id in (#{sql}) or #{self.table_name}.schema2_id in (#{sql})")
    end

    def schema1_manifest
      schema1.try(:docker_taggable)
    end

    def schema2_manifest
      schema2.try(:docker_taggable)
    end

    def self.with_uuid(ids)
      self.with_identifiers(ids)
    end

    def self.with_identifiers(ids)
      self.where(:id => ids)
    end

    def self.cleanup_tags
      self.where(:schema2_id => nil, :schema1_id => nil).delete_all
    end

    def self.import_meta_tags(repositories)
      repositories.each do |repo|
        tag_table_values = get_tag_table_values(repo)
        meta_tag_table_values = DockerMetaTag.where(:repository => repo).
                                  select(:schema1_id, :schema2_id, :name).map do |meta_tag|
          [meta_tag.schema1_id, meta_tag.schema2_id, meta_tag.name]
        end

        # Delete [meta_tag_table_values - tag_table_values], insert [tag_table_values - meta_tag_table_values]

        docker_meta_tag_arel_table = ::Katello::DockerMetaTag.arel_table
        params_to_query_for_delete = (meta_tag_table_values - tag_table_values).map do |schema1, schema2, name|
          conditional = docker_meta_tag_arel_table[:schema1_id].eq(schema1).and(
                        docker_meta_tag_arel_table[:schema2_id].eq(schema2)).and(
                        docker_meta_tag_arel_table[:name].eq(name)).to_sql

          "(#{conditional})"
        end

        unless params_to_query_for_delete.empty?
          ::Katello::DockerMetaTag.where(:repository => repo).
                                   where(params_to_query_for_delete.join(" OR ")).delete_all
        end

        (tag_table_values - meta_tag_table_values).each do |schema1, schema2, name|
          DockerMetaTag.where(:schema1_id => schema1,
                              :schema2_id => schema2,
                              :name => name,
                              :repository => repo).create!
        end
      end
    end

    def self.get_tag_table_values(repo)
      # queries DockerTags for a repo and retuns a [schema1, schema2 , name] tuple combination
      tags = ::Katello::DockerTag.where(:repository_id => repo.id)
      dups = tags.group_by(&:name)

      dups.map do |name, values|
        if values.first.docker_manifest.schema_version == 1
          schema1, schema2 = values
        else
          schema2, schema1 = values
        end
        [schema1.try(:id), schema2.try(:id), name]
      end
    end
  end
end
