require 'active_support/inflector'

module PolymorphicConstraints
  module ConnectionAdapters
    module PostgreSQLAdapter
      include BaseAdapter

      private

      def generate_upsert_constraints(relation, associated_table, polymorphic_models)
        unless polymorphic_models.any?
          raise "Must provide at least one polymorphic model for #{relation} on #{associated_table}"
        end

        associated_table = associated_table.to_s
        polymorphic_models = polymorphic_models.map(&:to_s).sort

        sql = <<-SQL
          CREATE FUNCTION check_#{associated_table}_#{relation}_upsert_integrity()
            RETURNS TRIGGER AS 'BEGIN
              IF NEW.#{relation}_type IS NULL AND NEW.#{relation}_id IS NULL THEN
                RETURN NEW;

              ELSEIF NEW.#{relation}_type NOT IN (#{polymorphic_models.map { |m| "''#{m.classify}''" }.join(',')}) THEN
                RAISE EXCEPTION ''Invalid polymorphic class specified (%).
                                Only #{polymorphic_models.map(&:classify).join(', ')} supported.'',
                                NEW.#{relation}_type;
                RETURN NULL;

              ELSEIF TG_OP = ''UPDATE'' AND OLD.#{relation}_type = NEW.#{relation}_type AND
                  OLD.#{relation}_id = NEW.#{relation}_id THEN
                RETURN NEW;
        SQL

        polymorphic_models.each do |polymorphic_model|
          sql << <<-SQL
            ELSEIF NEW.#{relation}_type = ''#{polymorphic_model.classify}'' AND
                   EXISTS (SELECT 1 FROM #{polymorphic_model.classify.constantize.table_name}
                           WHERE id = NEW.#{relation}_id) THEN
              RETURN NEW;
          SQL
        end

        sql << <<-SQL
            ELSE
              RAISE EXCEPTION ''Polymorphic record not found.
                                No % model with id %.'', NEW.#{relation}_type, NEW.#{relation}_id;
              RETURN NULL;
            END IF;
          END'
          LANGUAGE plpgsql;

          CREATE TRIGGER check_#{associated_table}_#{relation}_upsert_integrity_trigger
            BEFORE INSERT OR UPDATE ON #{associated_table}
            FOR EACH ROW
            EXECUTE PROCEDURE check_#{associated_table}_#{relation}_upsert_integrity();
        SQL

        strip_non_essential_spaces(sql)
      end

      def generate_delete_constraints(relation, associated_table, polymorphic_models)
        unless polymorphic_models.any?
          raise "Must provide at least one polymorphic model for #{relation} on #{associated_table}"
        end

        associated_table = associated_table.to_s
        polymorphic_models = polymorphic_models.map(&:to_s).sort

        sql = <<-SQL
          CREATE FUNCTION check_#{associated_table}_#{relation}_delete_integrity()
            RETURNS TRIGGER AS 'BEGIN
        SQL

        polymorphic_models.each_with_index do |polymorphic_model, index|
          sql << <<-SQL
            #{'ELSE' if index > 0}IF TG_TABLE_NAME = ''#{polymorphic_model.classify.constantize.table_name}'' AND
                   EXISTS (SELECT 1 FROM #{associated_table}
                           WHERE #{relation}_type = ''#{polymorphic_model.classify}''
                           AND #{relation}_id = OLD.id) THEN

              RAISE EXCEPTION ''Polymorphic reference exists.
                                There are records in #{associated_table} that refer to the table % with id %.
                                You must delete those records of table #{associated_table} first.'', TG_TABLE_NAME, OLD.id;
              RETURN NULL;
          SQL
        end

        sql << <<-SQL
              ELSE
                RETURN OLD;
              END IF;
            END'
          LANGUAGE plpgsql;
        SQL

        polymorphic_models.each do |polymorphic_model|
          table_name = polymorphic_model.classify.constantize.table_name

          sql << <<-SQL
            CREATE TRIGGER check_#{associated_table}_#{relation}_to_#{table_name}_delete_integrity_trigger
              BEFORE DELETE ON #{table_name}
              FOR EACH ROW
              EXECUTE PROCEDURE check_#{associated_table}_#{relation}_delete_integrity();
          SQL
        end

        strip_non_essential_spaces(sql)
      end

      def drop_constraints(relation, associated_table)
        sql = <<-SQL
          DROP FUNCTION IF EXISTS check_#{associated_table}_#{relation}_upsert_integrity() CASCADE;
          DROP FUNCTION IF EXISTS check_#{associated_table}_#{relation}_delete_integrity() CASCADE;
        SQL

        strip_non_essential_spaces(sql)
      end
    end

    module PostgreSQLAdapterExtension
      private

      def translate_exception(exception, message)
        message = message[:message] if message.is_a? Hash

        if message =~ /Polymorphic record not found./ ||
           message =~ /Invalid polymorphic class specified/ ||
           message =~ /Polymorphic reference exists./
          ActiveRecord::InvalidForeignKey.new message
        else
          super
        end
      end
    end
  end
end

PolymorphicConstraints::Adapter.safe_include :PostgreSQLAdapter, PolymorphicConstraints::ConnectionAdapters::PostgreSQLAdapter
ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.prepend PolymorphicConstraints::ConnectionAdapters::PostgreSQLAdapterExtension
