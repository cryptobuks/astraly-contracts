# https://github.com/dewi-tim/cairo-contracts/blob/feature-erc1155/src/openzeppelin/token/erc1155/ERC1155_Mintable_Burnable.cairo
%lang starknet

from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_not_zero, assert_not_equal
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.uint256 import Uint256, uint256_le, uint256_check
from openzeppelin.introspection.erc165.IERC165 import IERC165
from openzeppelin.security.safemath.library import SafeUint256

from InterfaceAll import IERC1155_Receiver
from contracts.utils import concat_arr

const IERC1155_interface_id = 0xd9b67a26
const IERC1155_MetadataURI_interface_id = 0x0e89341c
const IERC165_interface_id = 0x01ffc9a7

const IERC1155_RECEIVER_ID = 0x4e2312e0
const ON_ERC1155_RECEIVED_SELECTOR = 0xf23a6e61
const ON_BATCH_ERC1155_RECEIVED_SELECTOR = 0xbc197c81
const IACCOUNT_ID = 0xf10dbd44

#
# Events
#

@event
func TransferSingle(operator : felt, from_ : felt, to : felt, id : Uint256, value : Uint256):
end

@event
func TransferBatch(
    operator : felt,
    from_ : felt,
    to : felt,
    ids_len : felt,
    ids : Uint256*,
    values_len : felt,
    values : Uint256*,
):
end

@event
func ApprovalForAll(account : felt, operator : felt, approved : felt):
end

@event
func URI(value_len : felt, value : felt*, id : Uint256):
end

#
# Storage
#

@storage_var
func ERC1155_balances_(id : Uint256, account : felt) -> (balance : Uint256):
end

@storage_var
func ERC1155_operator_approvals_(account : felt, operator : felt) -> (approved : felt):
end

@storage_var
func ERC1155_uri_(index : felt) -> (uri : felt):
end

@storage_var
func ERC1155_uri_len_() -> (uri_len : felt):
end

#
# Constructor
#

func ERC1155_initializer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    uri_len_ : felt, uri_ : felt*
):
    _setURI(uri_len_, uri_)
    return ()
end

#
# Getters
#

func ERC1155_supportsInterface(interface_id : felt) -> (res : felt):
    # Less expensive (presumably) than storage
    if interface_id == IERC1155_interface_id:
        return (1)
    end
    if interface_id == IERC1155_MetadataURI_interface_id:
        return (1)
    end
    if interface_id == IERC165_interface_id:
        return (1)
    end
    return (0)
end

func ERC1155_uri{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(id : felt) -> (
    uri_len : felt, uri : felt*
):
    alloc_locals
    # let (uri) = ERC1155_uri_.read(id)

    # ERC1155 returns the same URI for all token types.
    # TokenId will be represented by the substring '{id}' and so stored in a felt
    # Client calling the function must replace the '{id}' substring with the actual token type ID
    let (tokenURI : felt*) = alloc()
    let (tokenURI_len : felt) = ERC1155_uri_len_.read()
    local index = 0
    _ERC1155_uri(tokenURI_len, tokenURI, index)

    return (uri_len=tokenURI_len, uri=tokenURI)
end

func _ERC1155_uri{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    uri_len : felt, uri : felt*, index : felt
):
    if index == uri_len:
        return ()
    end
    let (base) = ERC1155_uri_.read(index)
    assert [uri] = base
    _ERC1155_uri(uri_len=uri_len, uri=uri + 1, index=index + 1)
    return ()
end

func ERC1155_balanceOf{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    account : felt, id : Uint256
) -> (balance : Uint256):
    with_attr error_message("ERC1155: balance query for the zero address"):
        assert_not_zero(account)
    end
    let (balance) = ERC1155_balances_.read(id=id, account=account)
    return (balance)
end

func ERC1155_balanceOfBatch{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    accounts_len : felt, accounts : felt*, ids_len : felt, ids : Uint256*
) -> (batch_balances_len : felt, batch_balances : Uint256*):
    alloc_locals
    # Check args are equal length arrays
    with_attr error_message("ERC1155: accounts and ids length mismatch"):
        assert ids_len = accounts_len
    end
    # Allocate memory
    let (local batch_balances : Uint256*) = alloc()
    let len = accounts_len
    # Call iterator
    balance_of_batch_iter(len, accounts, ids, batch_balances)
    return (batch_balances_len=len, batch_balances=batch_balances)
end

func ERC1155_isApprovedForAll{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    account : felt, operator : felt
) -> (approved : felt):
    let (approved) = ERC1155_operator_approvals_.read(account=account, operator=operator)
    return (approved)
end

#
# Externals
#

func ERC1155_setApprovalForAll{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    operator : felt, approved : felt
):
    let (caller) = get_caller_address()
    # Non-zero caller asserted in called function
    _set_approval_for_all(owner=caller, operator=operator, approved=approved)
    return ()
end

func ERC1155_setURI{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    new_uri_len : felt, new_uri : felt*
):
    _setURI(new_uri_len, new_uri)
    return ()
end

func ERC1155_safeTransferFrom{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    from_ : felt, to : felt, id : Uint256, amount : Uint256, data_len : felt, data : felt*
):
    let (caller) = get_caller_address()
    with_attr error_message("ERC1155: called from zero address"):
        assert_not_zero(caller)
    end
    with_attr error_message("ERC1155: caller is not owner nor approved"):
        owner_or_approved(from_)
    end
    _safe_transfer_from(from_, to, id, amount, data_len, data)
    return ()
end

func ERC1155_safeBatchTransferFrom{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr
}(
    from_ : felt,
    to : felt,
    ids_len : felt,
    ids : Uint256*,
    amounts_len : felt,
    amounts : Uint256*,
    data_len : felt,
    data : felt*,
):
    let (caller) = get_caller_address()
    with_attr error_message("ERC1155: called from zero address"):
        assert_not_zero(caller)
    end
    with_attr error_message("ERC1155: transfer caller is not owner nor approved"):
        owner_or_approved(from_)
    end
    return _safe_batch_transfer_from(from_, to, ids_len, ids, amounts_len, amounts, data_len, data)
end

#
# Internals
#

func _safe_transfer_from{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    from_ : felt, to : felt, id : Uint256, amount : Uint256, data_len : felt, data : felt*
):
    alloc_locals
    # Check args
    with_attr error_message("ERC1155: transfer to the zero address"):
        assert_not_zero(to)
    end
    with_attr error_message("ERC1155: invalid uint in calldata"):
        uint256_check(id)
        uint256_check(amount)
    end
    # Todo: beforeTokenTransfer

    # Check balance sufficient
    let (local from_balance) = ERC1155_balances_.read(id=id, account=from_)
    let (sufficient_balance) = uint256_le(amount, from_balance)
    with_attr error_message("ERC1155: insufficient balance for transfer"):
        assert_not_zero(sufficient_balance)
    end
    # Deduct from sender
    let (new_balance : Uint256) = SafeUint256.sub_le(from_balance, amount)
    ERC1155_balances_.write(id=id, account=from_, value=new_balance)

    # Add to reicever
    let (to_balance : Uint256) = ERC1155_balances_.read(id=id, account=to)
    let (new_balance : Uint256) = SafeUint256.add(to_balance, amount)
    ERC1155_balances_.write(id=id, account=to, value=new_balance)

    let (operator) = get_caller_address()

    TransferSingle.emit(operator, from_, to, id, amount)

    _do_safe_transfer_acceptance_check(operator, from_, to, id, amount, data_len, data)

    return ()
end

func _safe_batch_transfer_from{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    from_ : felt,
    to : felt,
    ids_len : felt,
    ids : Uint256*,
    amounts_len : felt,
    amounts : Uint256*,
    data_len : felt,
    data : felt*,
):
    alloc_locals
    with_attr error_message("ERC1155: ids and amounts length mismatch"):
        assert_not_zero(to)
    end
    # Check args are equal length arrays
    with_attr error_message("ERC1155: transfer to the zero address"):
        assert ids_len = amounts_len
    end
    # Recursive call
    let len = ids_len
    safe_batch_transfer_from_iter(from_, to, len, ids, amounts)
    let (operator) = get_caller_address()
    TransferBatch.emit(operator, from_, to, ids_len, ids, amounts_len, amounts)
    _do_safe_batch_transfer_acceptance_check(
        operator, from_, to, ids_len, ids, amounts_len, amounts, data_len, data
    )
    return ()
end

func ERC1155_mint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    to : felt, id : Uint256, amount : Uint256, data_len : felt, data : felt*
):
    let (caller) = get_caller_address()
    with_attr error_message("ERC1155: called from zero address"):
        assert_not_zero(caller)
    end
    # Cannot mint to zero address
    with_attr error_message("ERC1155: mint to the zero address"):
        assert_not_zero(to)
    end
    # Check uints valid
    with_attr error_message("ERC1155: invalid uint256 in calldata"):
        uint256_check(id)
        uint256_check(amount)
    end
    # beforeTokenTransfer
    # add to minter check for overflow
    let (to_balance : Uint256) = ERC1155_balances_.read(id=id, account=to)
    let (new_balance : Uint256) = SafeUint256.add(to_balance, amount)
    ERC1155_balances_.write(id=id, account=to, value=new_balance)
    # doSafeTransferAcceptanceCheck
    let (operator) = get_caller_address()
    TransferSingle.emit(operator=operator, from_=0, to=to, id=id, value=amount)
    _do_safe_transfer_acceptance_check(operator, 0, to, id, amount, data_len, data)

    return ()
end

func ERC1155_mint_batch{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    to : felt,
    ids_len : felt,
    ids : Uint256*,
    amounts_len : felt,
    amounts : Uint256*,
    data_len : felt,
    data : felt*,
):
    alloc_locals
    let (caller) = get_caller_address()
    with_attr error_message("ERC1155: called from zero address"):
        assert_not_zero(caller)
    end
    # Cannot mint to zero address
    with_attr error_message("ERC1155: mint to the zero address"):
        assert_not_zero(to)
    end
    # Check args are equal length arrays
    with_attr error_message("ERC1155: ids and amounts length mismatch"):
        assert ids_len = amounts_len
    end
    # Recursive call
    let len = ids_len
    mint_batch_iter(to, len, ids, amounts)
    let (operator) = get_caller_address()
    TransferBatch.emit(
        operator=operator,
        from_=0,
        to=to,
        ids_len=ids_len,
        ids=ids,
        values_len=amounts_len,
        values=amounts,
    )
    _do_safe_batch_transfer_acceptance_check(
        operator, 0, to, ids_len, ids, amounts_len, amounts, data_len, data
    )
    return ()
end

func ERC1155_burn{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    from_ : felt, id : Uint256, amount : Uint256
):
    alloc_locals
    let (caller) = get_caller_address()
    with_attr error_message("ERC1155: called from zero address"):
        assert_not_zero(caller)
    end
    with_attr error_message("ERC1155: burn from the zero address"):
        assert_not_zero(from_)
    end
    # beforeTokenTransfer
    # Check balance sufficient
    let (local from_balance) = ERC1155_balances_.read(id=id, account=from_)
    let (sufficient_balance) = uint256_le(amount, from_balance)
    with_attr error_message("ERC1155: burn amount exceeds balance"):
        assert_not_zero(sufficient_balance)
    end
    # Deduct from burner
    let (new_balance : Uint256) = SafeUint256.sub_le(from_balance, amount)
    ERC1155_balances_.write(id=id, account=from_, value=new_balance)
    let (operator) = get_caller_address()
    TransferSingle.emit(operator=operator, from_=from_, to=0, id=id, value=amount)
    return ()
end

func ERC1155_burn_batch{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    from_ : felt, ids_len : felt, ids : Uint256*, amounts_len : felt, amounts : Uint256*
):
    alloc_locals
    let (caller) = get_caller_address()
    with_attr error_message("ERC1155: called from zero address"):
        assert_not_zero(caller)
    end
    with_attr error_message("ERC1155: burn from the zero address"):
        assert_not_zero(from_)
    end
    # Check args are equal length arrays
    with_attr error_message("ERC1155: ids and amounts length mismatch"):
        assert ids_len = amounts_len
    end
    # Recursive call
    let len = ids_len
    burn_batch_iter(from_, len, ids, amounts)
    let (operator) = get_caller_address()
    TransferBatch.emit(
        operator=operator,
        from_=from_,
        to=0,
        ids_len=ids_len,
        ids=ids,
        values_len=amounts_len,
        values=amounts,
    )
    return ()
end

#
# Internals
#

func _set_approval_for_all{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    owner : felt, operator : felt, approved : felt
):
    # check approved is bool
    assert approved * (approved - 1) = 0
    # since caller can now be 0
    with_attr error_message("ERC1155: setting approval status for zero address"):
        assert_not_zero(owner * operator)
    end
    with_attr error_message("ERC1155: setting approval status for self"):
        assert_not_equal(owner, operator)
    end
    ERC1155_operator_approvals_.write(owner, operator, approved)
    ApprovalForAll.emit(owner, operator, approved)
    return ()
end

func _setURI{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    uri_len : felt, newuri : felt*
):
    alloc_locals
    ERC1155_uri_len_.write(uri_len)
    local uri_index = 0
    _populate_uri_array(uri_len, newuri, uri_index)
    return ()
end

func _do_safe_transfer_acceptance_check{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr
}(
    operator : felt,
    from_ : felt,
    to : felt,
    id : Uint256,
    amount : Uint256,
    data_len : felt,
    data : felt*,
):
    let (caller) = get_caller_address()
    # ERC1155_RECEIVER_ID = 0x4e2312e0
    let (is_supported) = IERC165.supportsInterface(to, IERC1155_RECEIVER_ID)
    if is_supported == 1:
        let (selector) = IERC1155_Receiver.onERC1155Received(
            to, operator, from_, id, amount, data_len, data
        )

        # onERC1155Recieved selector
        with_attr error_message("ERC1155: ERC1155Receiver rejected tokens"):
            assert selector = ON_ERC1155_RECEIVED_SELECTOR
        end
        return ()
    end
    let (is_account) = IERC165.supportsInterface(to, IACCOUNT_ID)
    with_attr error_message("ERC1155: transfer to non ERC1155Receiver implementer"):
        assert_not_zero(is_account)
    end
    # IAccount_ID = 0x50b70dcb
    return ()
end

func _do_safe_batch_transfer_acceptance_check{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr
}(
    operator : felt,
    from_ : felt,
    to : felt,
    ids_len : felt,
    ids : Uint256*,
    amounts_len : felt,
    amounts : Uint256*,
    data_len : felt,
    data : felt*,
):
    let (caller) = get_caller_address()
    # Confirm supports IERC1155Reciever interface
    let (is_supported) = IERC165.supportsInterface(to, IERC1155_RECEIVER_ID)
    if is_supported == 1:
        let (selector) = IERC1155_Receiver.onERC1155BatchReceived(
            to, operator, from_, ids_len, ids, amounts_len, amounts, data_len, data
        )

        # Confirm onBatchERC1155Recieved selector returned
        with_attr error_message("ERC1155: ERC1155Receiver rejected tokens"):
            assert selector = ON_BATCH_ERC1155_RECEIVED_SELECTOR
        end
        return ()
    end

    # Alternatively confirm EOA
    let (is_account) = IERC165.supportsInterface(to, IACCOUNT_ID)
    with_attr error_message("ERC1155: transfer to non ERC1155Receiver implementer"):
        assert_not_zero(is_account)
    end
    return ()
end

#
# Helpers
#

func balance_of_batch_iter{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    len : felt, accounts : felt*, ids : Uint256*, batch_balances : Uint256*
):
    if len == 0:
        return ()
    end
    # may be unnecessary now
    # Read current entries, Todo: perform Uint256 checks
    let id : Uint256 = [ids]
    uint256_check(id)
    let account : felt = [accounts]

    let (balance : Uint256) = ERC1155_balanceOf(account, id)
    assert [batch_balances] = balance
    return balance_of_batch_iter(
        len - 1, accounts + 1, ids + Uint256.SIZE, batch_balances + Uint256.SIZE
    )
end

func safe_batch_transfer_from_iter{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr
}(from_ : felt, to : felt, len : felt, ids : Uint256*, amounts : Uint256*):
    # Base case
    alloc_locals
    if len == 0:
        return ()
    end

    # Read current entries,  perform Uint256 checks
    let id = [ids]
    with_attr error_message("ERC1155: invalid uint in calldata"):
        uint256_check(id)
    end
    let amount = [amounts]
    with_attr error_message("ERC1155: invalid uint in calldata"):
        uint256_check(amount)
    end

    # Check balance is sufficient
    let (from_balance) = ERC1155_balances_.read(id=id, account=from_)
    let (sufficient_balance) = uint256_le(amount, from_balance)
    with_attr error_message("ERC1155: insufficient balance for transfer"):
        assert_not_zero(sufficient_balance)
    end
    # deduct from
    let (new_balance : Uint256) = SafeUint256.sub_le(from_balance, amount)
    ERC1155_balances_.write(id=id, account=from_, value=new_balance)

    # add to
    let (to_balance : Uint256) = ERC1155_balances_.read(id=id, account=to)
    let (new_balance : Uint256) = SafeUint256.add(to_balance, amount)
    ERC1155_balances_.write(id=id, account=to, value=new_balance)

    # Recursive call
    return safe_batch_transfer_from_iter(
        from_, to, len - 1, ids + Uint256.SIZE, amounts + Uint256.SIZE
    )
end

func mint_batch_iter{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    to : felt, len : felt, ids : Uint256*, amounts : Uint256*
):
    # Base case
    alloc_locals
    if len == 0:
        return ()
    end

    # Read current entries, Todo: perform Uint256 checks
    let id : Uint256 = [ids]
    let amount : Uint256 = [amounts]
    with_attr error_message("ERC1155: invalid uint256 in calldata"):
        uint256_check(id)
        uint256_check(amount)
    end
    # add to
    let (to_balance : Uint256) = ERC1155_balances_.read(id=id, account=to)
    let (new_balance : Uint256) = SafeUint256.add(to_balance, amount)
    ERC1155_balances_.write(id=id, account=to, value=new_balance)

    # Recursive call
    return mint_batch_iter(to, len - 1, ids + Uint256.SIZE, amounts + Uint256.SIZE)
end

func burn_batch_iter{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    from_ : felt, len : felt, ids : Uint256*, amounts : Uint256*
):
    # Base case
    alloc_locals
    if len == 0:
        return ()
    end

    # Read current entries, Todo: perform Uint256 checks
    let id : Uint256 = [ids]
    with_attr error_message("ERC1155: invalid uint in calldata"):
        uint256_check(id)
    end
    let amount : Uint256 = [amounts]
    with_attr error_message("ERC1155: invalid uint in calldata"):
        uint256_check(amount)
    end

    # Check balance is sufficient
    let (from_balance) = ERC1155_balances_.read(id=id, account=from_)
    let (sufficient_balance) = uint256_le(amount, from_balance)
    with_attr error_message("ERC1155: burn amount exceeds balance"):
        assert_not_zero(sufficient_balance)
    end

    # deduct from
    let (new_balance : Uint256) = SafeUint256.sub_le(from_balance, amount)
    ERC1155_balances_.write(id=id, account=from_, value=new_balance)

    # Recursive call
    return burn_batch_iter(from_, len - 1, ids + Uint256.SIZE, amounts + Uint256.SIZE)
end

func owner_or_approved{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(owner):
    let (caller) = get_caller_address()
    if caller == owner:
        return ()
    end
    let (approved) = ERC1155_isApprovedForAll(owner, caller)
    assert approved = 1
    return ()
end

func _populate_uri_array{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    len : felt, _uri : felt*, index : felt
):
    if index == len:
        return ()
    end

    with_attr error_message("ERC1155: uri can't be null"):
        assert_not_zero(_uri[index])
    end

    ERC1155_uri_.write(index, _uri[index])
    _populate_uri_array(len=len, _uri=_uri, index=index + 1)
    return ()
end
