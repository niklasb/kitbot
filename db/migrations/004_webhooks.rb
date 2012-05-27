Sequel.migration do
  change do
    create_table(:webhooks) do
      primary_key :id
      String :user, :null => false
      String :url, :null => false
      String :channel, :null => false
      String :hook, :null => false
      String :argument, :null => false
      Integer :fails, :null => false, :default => 0
    end
  end
end
