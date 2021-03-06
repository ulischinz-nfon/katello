module Katello
  module Pulp
    class Repository
      class Ostree < ::Katello::Pulp::Repository
        PULP_MIRROR_SYNC_DEPTH = -1

        def generate_master_importer
          config = {
            feed: root.url,
            depth: root.compute_ostree_upstream_sync_depth
          }
          Runcible::Models::OstreeImporter.new(config.merge(master_importer_connection_options))
        end

        def generate_mirror_importer
          config = {
            feed: root.url,
            depth: PULP_MIRROR_SYNC_DEPTH
          }
          Runcible::Models::OstreeImporter.new(config.merge(mirror_importer_connection_options))
        end

        def generate_distributors
          [Runcible::Models::OstreeDistributor.new(:id => repo.pulp_id,
                                                  :auto_publish => true,
                                                  :relative_path => repo.relative_path,
                                                  :depth => root.compute_ostree_upstream_sync_depth)]
        end

        def partial_repo_path
          "/pulp/puppet/#{pulp_id}/"
        end

        def importer_class
          Runcible::Models::OstreeImporter
        end
      end
    end
  end
end
