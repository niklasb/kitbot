Sequel.migration do
  change do
    create_table(:api_users) do
      String :user, :null => false, :primary_key => true
      String :password, :null => false
    end
  end
end
