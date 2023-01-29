module dev_account::events {
    use aptos_framework::event;
    use aptos_framework::account;
    use std::signer;
    friend dev_account::init;

    struct EventsStore<phantom X, phantom Y> has key {
        pool_created_handle: event::EventHandle<PoolCreatedEvent<X, Y>>,
        liquidity_added_handle: event::EventHandle<AddLiquidityEvent<X, Y>>,
        liquidity_removed_handle: event::EventHandle<RemoveLiquidityEvent<X, Y>>,
        swap_handle: event::EventHandle<SwapEvent<X, Y>>,
        oracle_updated_handle: event::EventHandle<OracleUpdatedEvent<X, Y>>,
        update_fee_handle: event::EventHandle<UpdateFeeEvent<X, Y>>,
        update_dao_fee_handle: event::EventHandle<UpdateDAOEvent<X, Y>>,
    }

    struct PoolCreatedEvent<phantom X, phantom Y> has drop, store {
        creator: address,
    }

    struct AddLiquidityEvent<phantom X, phantom Y> has drop, store {
        amount_x: u64,
        amount_y: u64,
        lp_tokens_received: u64,
    }

    struct RemoveLiquidityEvent<phantom X, phantom Y> has drop, store {
        amount_x: u64,
        amount_y: u64,
        lp_tokens_burned: u64,
    }

    struct SwapEvent<phantom X, phantom Y> has drop, store {
        x_in: u64,
        x_out: u64,
        y_in: u64,
        y_out: u64,
    }

    struct OracleUpdatedEvent<phantom X, phantom Y> has drop, store {
        last_x_price: u128,
        last_y_price: u128,
    }

    struct UpdateFeeEvent<phantom X, phantom Y> has drop, store {
        new_fee: u64,
    }

    struct UpdateDAOEvent<phantom X, phantom Y> has drop, store {
        new_fee: u64,
    }

    public(friend) fun initialize_event<X,Y>(resource_signer:&signer){
        let events_store = EventsStore<X, Y> {
            pool_created_handle: account::new_event_handle(resource_signer),
            liquidity_added_handle: account::new_event_handle(resource_signer),
            liquidity_removed_handle: account::new_event_handle(resource_signer),
            swap_handle: account::new_event_handle(resource_signer),
            oracle_updated_handle: account::new_event_handle(resource_signer),
            update_fee_handle: account::new_event_handle(resource_signer),
            update_dao_fee_handle: account::new_event_handle(resource_signer),
        };
        event::emit_event(
            &mut events_store.pool_created_handle,
            PoolCreatedEvent<X, Y> {
                creator: signer::address_of(resource_signer)
            },
        );
        move_to(resource_signer, events_store);
    }

    public(friend) fun added_event<X, Y>(
        added_x:u64,
        added_y: u64,
        provided_liq: u64,
    ) acquires EventsStore {
        let events_store = borrow_global_mut<EventsStore<X, Y>>(@dev_account);
        event::emit_event(
            &mut events_store.liquidity_added_handle,
            AddLiquidityEvent<X, Y> {
                amount_x: added_x,
                amount_y: added_y,
                lp_tokens_received: provided_liq
            });
    }

    public(friend) fun remove_event<X, Y>(
        x_to_return_val:u64,
        y_to_return_val: u64,
        lp_coins_burning_val: u64,
    ) acquires EventsStore {
        let events_store = borrow_global_mut<EventsStore<X, Y>>(@dev_account);
        event::emit_event(
            &mut events_store.liquidity_removed_handle,
            RemoveLiquidityEvent<X, Y> {
                amount_x: x_to_return_val,
                amount_y: y_to_return_val,
                lp_tokens_burned: lp_coins_burning_val
            });
    }

    public(friend) fun swap_event<X, Y>(
        x_in_val:u64,
        y_in_val: u64,
        x_out: u64,
        y_out: u64,
    ) acquires EventsStore {
        let events_store = borrow_global_mut<EventsStore<X, Y>>(@dev_account);
        event::emit_event(
            &mut events_store.swap_handle,
            SwapEvent<X, Y> {
                x_in: x_in_val,
                y_in: y_in_val,
                x_out,
                y_out,
        });
    }

    public(friend) fun oracle_event<X, Y>(
        x_price:u128,
        y_price:u128,
    ) acquires EventsStore {
        let events_store = borrow_global_mut<EventsStore<X, Y>>(@dev_account);
        event::emit_event(
            &mut events_store.oracle_updated_handle,
            OracleUpdatedEvent<X, Y> {
                last_x_price: x_price,
                last_y_price: y_price,
            });
    }

    public(friend) fun set_fee_event<X, Y>(
        fee:u64,
    ) acquires EventsStore {
        let event_store = borrow_global_mut<EventsStore<X,Y>>(@dev_account);
        event::emit_event(
            &mut event_store.update_fee_handle,
            UpdateFeeEvent<X, Y> { new_fee: fee }
        );
    }

    public(friend) fun set_dao_event<X, Y>(
        dao_fee:u64,
    ) acquires EventsStore {
        let event_store = borrow_global_mut<EventsStore<X,Y>>(@dev_account);
        event::emit_event(
            &mut event_store.update_dao_fee_handle,{
                UpdateDAOEvent<X, Y> { new_fee: dao_fee }
            }
        )
    }
}