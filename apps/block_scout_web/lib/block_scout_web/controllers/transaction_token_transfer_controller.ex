defmodule BlockScoutWeb.TransactionTokenTransferController do
  use BlockScoutWeb, :controller

  import BlockScoutWeb.Chain, only: [paging_options: 1, next_page_params: 3, split_list_by_page: 1]

  alias BlockScoutWeb.{AccessHelpers, TransactionTokenTransferView, TransactionView}
  alias Explorer.{Chain, Market}
  alias Explorer.ExchangeRates.Token
  alias Phoenix.View

  {:ok, burn_address_hash} = Chain.string_to_address_hash("0x0000000000000000000000000000000000000000")
  @burn_address_hash burn_address_hash

  def index(conn, %{"transaction_id" => transaction_hash_string, "type" => "JSON"} = params) do
    with {:ok, transaction_hash} <- Chain.string_to_transaction_hash(transaction_hash_string),
         :ok <- Chain.check_transaction_exists(transaction_hash),
         {:ok, transaction} <-
           Chain.hash_to_transaction(
             transaction_hash,
             []
           ),
         {:ok, false} <- AccessHelpers.restricted_access?(to_string(transaction.from_address_hash), params),
         {:ok, false} <- AccessHelpers.restricted_access?(to_string(transaction.to_address_hash), params) do
      full_options =
        Keyword.merge(
          [
            necessity_by_association: %{
              from_address: :required,
              to_address: :required,
              token: :required
            }
          ],
          paging_options(params)
        )

      token_transfers_plus_one = Chain.transaction_to_token_transfers(transaction_hash, full_options)

      {token_transfers, next_page} = split_list_by_page(token_transfers_plus_one)

      next_page_url =
        case next_page_params(next_page, token_transfers, params) do
          nil ->
            nil

          next_page_params ->
            transaction_token_transfer_path(conn, :index, transaction_hash, Map.delete(next_page_params, "type"))
        end

      items =
        token_transfers
        |> Enum.map(fn transfer ->
          View.render_to_string(
            TransactionTokenTransferView,
            "_token_transfer.html",
            token_transfer: transfer,
            burn_address_hash: @burn_address_hash,
            conn: conn
          )
        end)

      json(
        conn,
        %{
          items: items,
          next_page_path: next_page_url
        }
      )
    else
      {:restricted_access, _} ->
        conn
        |> put_status(404)
        |> put_view(TransactionView)
        |> render("not_found.html", transaction_hash: transaction_hash_string)

      :error ->
        conn
        |> put_status(422)
        |> put_view(TransactionView)
        |> render("invalid.html", transaction_hash: transaction_hash_string)

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> put_view(TransactionView)
        |> render("not_found.html", transaction_hash: transaction_hash_string)

      :not_found ->
        conn
        |> put_status(404)
        |> put_view(TransactionView)
        |> render("not_found.html", transaction_hash: transaction_hash_string)
    end
  end

  def index(conn, %{"transaction_id" => transaction_hash_string} = params) do
    with {:ok, transaction_hash} <- Chain.string_to_transaction_hash(transaction_hash_string),
         {:ok, transaction} <-
           Chain.hash_to_transaction(
             transaction_hash,
             necessity_by_association: %{
               :block => :optional,
               [created_contract_address: :names] => :optional,
               [from_address: :names] => :optional,
               [to_address: :names] => :optional,
               [to_address: :smart_contract] => :optional,
               :token_transfers => :optional
             }
           ),
         {:ok, didlog} <- Chain.didlog_to_transaction(transaction_hash),
         {:ok, false} <- AccessHelpers.restricted_access?(to_string(transaction.from_address_hash), params),
         {:ok, false} <- AccessHelpers.restricted_access?(to_string(transaction.to_address_hash), params) do
      render(
        conn,
        "index.html",
        exchange_rate: Market.get_exchange_rate(Explorer.coin()) || Token.null(),
        block_height: Chain.block_height(),
        current_path: current_path(conn),
        show_token_transfers: true,
        didlog: didlog,
        transaction: transaction
      )
    else
      :not_found ->
        conn
        |> put_status(404)
        |> put_view(TransactionView)
        |> render("not_found.html", transaction_hash: transaction_hash_string)

      :error ->
        conn
        |> put_status(422)
        |> put_view(TransactionView)
        |> render("invalid.html", transaction_hash: transaction_hash_string)

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> put_view(TransactionView)
        |> render("not_found.html", transaction_hash: transaction_hash_string)

      {:restricted_access, _} ->
        conn
        |> put_status(404)
        |> put_view(TransactionView)
        |> render("not_found.html", transaction_hash: transaction_hash_string)
    end
  end
end
