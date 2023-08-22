module SolidCache
  class Entry < Record
    NULL_INSTRUMENTER = ActiveSupport::Notifications::Instrumenter.new(ActiveSupport::Notifications::Fanout.new)

    class << self

      def set(key, value)
        upsert_all([{key: key, value: value}], unique_by: upsert_unique_by, update_only: [:value])
      end

      def set_all(payloads)
        upsert_all(payloads, unique_by: upsert_unique_by, update_only: [:value])
      end

      def get(key)
        uncached do
          disable_instrumentation do
            find_by_sql([get_sql, ActiveModel::Type::Binary.new.serialize(key)]).pick(:value)
          end
        end
      end

      def get_all(keys)
        serialized_keys = keys.map { |key| ActiveModel::Type::Binary.new.serialize(key) }
        uncached do
          disable_instrumentation do
            find_by_sql([get_all_sql, serialized_keys]).pluck(:key, :value).to_h
          end
        end
      end

      def delete_by_key(key)
        where(key: key).delete_all.nonzero?
      end

      def delete_matched(matcher, batch_size:)
        like_matcher = arel_table[:key].matches(matcher, nil, true)
        where(like_matcher).select(:id).find_in_batches(batch_size: batch_size) do |entries|
          delete_by(id: entries.map(&:id))
        end
      end

      def increment(key, amount)
        transaction do
          amount += lock.where(key: key).pick(:value).to_i
          set(key, amount)
          amount
        end
      end

      def touch_by_ids(ids)
        where(id: ids).touch_all
      end

      def id_range
        pick(Arel.sql("max(id) - min(id) + 1")) || 0
      end

      private
        def upsert_unique_by
          connection.supports_insert_conflict_target? ? :key : nil
        end

        def get_sql
          @get_sql ||= build_sql_with_binds(SolidCache::Entry.where(key: "placeholder").select(:value))
        end

        def get_all_sql
          @get_all_sql ||= build_sql_with_binds(SolidCache::Entry.where(key: ["placeholder1", "placeholder2"]).select(:key, :value)).gsub("?, ?", "?")
        end

        def build_sql_with_binds(relation)
          collector = Arel::Collectors::Composite.new(
            Arel::Collectors::SQLString.new,
            Arel::Collectors::Bind.new,
          )

          SolidCache::Entry.connection.visitor.compile(relation.arel.ast, collector)[0]
        end
    end
  end
end

ActiveSupport.run_load_hooks :solid_cache_entry, SolidCache::Entry

