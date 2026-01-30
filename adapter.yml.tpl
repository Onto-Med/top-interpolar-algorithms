id: interpolar_adapter
adapter: care.smith.top.top_phenotypic_query.adapter.sql.InterpolarAdapter
connection:
  url: jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}
  user: ${DB_USER}
  password: ${DB_PASS}
