module PolymorphicConstraints
  module ConnectionAdapters
    module Table
      def polymorphic_constraints(relation, options = {})
        @base.add_polymorphic_constraints(relation, @table_name, options)
      end

      def remove_polymorphic_constraints(relation, options = {})
        @base.remove_polymorphic_constraints(relation, options)
      end
    end
  end
end