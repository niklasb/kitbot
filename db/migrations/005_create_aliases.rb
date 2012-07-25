Sequel.migration do
  change do
    create_table(:aliases) do
      String :alias, :null => false, :primary_key => true
      String :user, :null => false
    end
  end
end
