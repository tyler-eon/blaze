defmodule Blaze.API do
  @moduledoc """
  A wrapper around `GoogleApi.Firestore.V1.Api.Projects` with simpler function
  names and automatic conversion between native Elixir types and Firestore
  models.

  ## Connections

  All connections are required to be Tesla connections, because that's what the
  official API library requires. However, you can create your own Tesla
  connection if you wish; the first parameter of every API function is a `conn`.
  If you don't want to create your own Tesla connection you may also use
  `connection/1`, passing in a `Goth` token, which will generate a valid Tesla
  connection for you. For example:

  ```elixir
  token = Goth.Token.for_scope(scope)
  conn = Blaze.API.connection(token.token)
  ```

  This doesn't do much except wrap `GoogleApi.Firestore.V1.Connection.new/1`,
  but this way you can alias/import a single module (`Blaze.API`) rather than
  having to start including the official library modules. After all, this
  wrapper aims to completely remove the need to directly interact with the messy
  official API library.
  """

  alias GoogleApi.Firestore.V1.Api.Projects
  alias GoogleApi.Firestore.V1.Connection

  alias GoogleApi.Firestore.V1.Model.{
    Empty,
    ListDocumentsResponse,
    RunQueryRequest,
    RunQueryResponse
  }

  @doc """
  Create a new Firestore connection.
  """
  def connection(token), do: Connection.new(token)

  @doc """
  Creates a new document. This will encode a native Elixir map to a document
  request prior to creation, as well as decoding the returned document model
  into a native Elixir map in the case of a successful response.
  """
  def create_document(conn, parent, collection, data, opts \\ []) do
    conn
    |> Projects.firestore_projects_databases_documents_create_document(
      parent,
      collection,
      Keyword.put(opts, :body, Blaze.Document.encode(data))
    )
    |> parse_documents()
  end

  @doc """
  Returns a document at the given path. This is typically the fully-qualified
  collection path plus the document id. E.g.
  `projects/project-id/databases/(default)/documents/some_collection/document_id`.

  If you do not have the unique identifier for a given document, you may query
  for the document first by using `list_documents/3` or `run_query/3`.
  """
  def get_document(conn, path, opts \\ []) do
    conn
    |> Projects.firestore_projects_databases_documents_get(
      path,
      opts
    )
    |> parse_documents()
  end

  @doc """
  Updates a document at the given path. This is typically the fully-qualified
  collection path plus the document id. E.g.
  `projects/project-id/databases/(default)/documents/some_collection/document_id`.

  If a document does not exist at that path, a document is created.
  """
  def update_document(conn, path, data, opts \\ []) do
    conn
    |> Projects.firestore_projects_databases_documents_patch(
      path,
      Keyword.put(opts, :body, Blaze.Document.encode(data))
    )
    |> parse_documents()
  end

  @doc """
  Deletes a document at the given path. This is typically the fully-qualified
  collection path plus the document id. E.g.
  `projects/project-id/databases/(default)/documents/some_collection/document_id`.

  If you do not have the unique identifier for a given document, you may query
  for the document first by using `list_documents/3` or `run_query/3`.
  """
  def delete_document(conn, path, opts \\ []) do
    conn
    |> Projects.firestore_projects_databases_documents_delete(
      path,
      opts
    )
    |> parse_documents()
  end

  @doc """
  List all documents stored within a given collection. You may use `:pageSize`
  and `:pageToken` in the `opts` list to control how many results are returned
  per page as well as which page to start on.
  """
  def list_documents(conn, parent, collection, opts \\ []) do
    conn
    |> Projects.firestore_projects_databases_documents_list(
      parent,
      collection,
      opts
    )
    |> parse_documents()
  end

  @doc """
  Runs a structured query against the database. It is recommended to use
  `Blaze.Query` to build the structured query model to pass to this function.
  """
  def run_query(conn, parent, query, opts \\ []) do
    conn
    |> Projects.firestore_projects_databases_documents_run_query(
      parent,
      Keyword.put(opts, :body, %RunQueryRequest{structuredQuery: query})
    )
    |> parse_documents()
  end

  @doc """
  Parse a document response tuple so that any returned documents are native
  Elixir maps rather than Document models.
  """
  @spec parse_documents(term) :: term
  def parse_documents({:ok, %Empty{}}), do: {:ok, []}

  def parse_documents({:ok, %ListDocumentsResponse{documents: nil}}),
    do: {:ok, []}

  def parse_documents({:ok, %ListDocumentsResponse{documents: docs, nextPageToken: npt}}) do
    {:ok,
     %{
       documents: docs |> Enum.map(&Blaze.Document.decode/1),
       nextPageToken: npt
     }}
  end

  def parse_documents({:ok, docs}) when is_list(docs) do
    # Yet another ridiculous thing about the API - instead of returning a single
    # top-level query response object with a list of results, the `RunQuery`
    # API returns a list of `RunQueryResponse` models that each contain a single
    # document. We address that here in our custom `Enum.map` block, extracting
    # the document before decoding.
    documents =
      Enum.map(docs, fn
        %RunQueryResponse{document: doc} -> Blaze.Document.decode(doc)
        doc -> Blaze.Document.decode(doc)
      end)

    {:ok, documents}
  end

  def parse_documents({:ok, doc}), do: {:ok, Blaze.Document.decode(doc)}
  def parse_documents(response), do: response
end
