module PolymorphicConstraints
  module Utils
    module PolymorphicModelFinder
      def get_polymorphic_models(relation, associated_table)
        Rails.application.eager_load!
        base_class.descendants.select do |klass|
          contains_polymorphic_relation?(klass, relation, associated_table)
        end
      end

      private

      def contains_polymorphic_relation?(model_class, relation, associated_table)
        associations = model_class.reflect_on_all_associations
        associations.any? { |r| r.name == associated_table && r.options[:as] == relation.to_sym }
      end

      def base_class
        defined?(ApplicationRecord) ? ApplicationRecord : ActiveRecord::Base
      end
    end
  end
end