module dev_account::dao {

    use aptos_framework::coin::Coin;
    use aptos_framework::coin;
    use aptos_framework::event;
    use aptos_framework::account;
    use std::signer;
    use dev_account::global_config;

    const ERR_NOT_PERMITTED:u64=222;

    friend dev_account::init;
    struct DaoAdmin<phantom X, phantom Y> has key {
        coin_x:Coin<X>,
        coin_y:Coin<Y>,
    }

    struct DaoEventsStore<phantom X,phantom Y> has key {
        register_dao_handle: event::EventHandle<DaoRegisterEvent<X,Y>>,
        add_dao_handle: event::EventHandle<DaoAddEvent<X,Y>>,
        withdraw_dao_handle: event::EventHandle<DaoRemoveEvent<X,Y>>,
    }

    struct DaoRegisterEvent<phantom X,phantom Y> has store,drop{}

    struct DaoAddEvent<phantom X,phantom Y> has store,drop{
        x_val:u64,
        y_val:u64,
    }
    struct DaoRemoveEvent<phantom X,phantom Y> has store,drop{
        x_val:u64,
        y_val:u64,
    }

    public fun initialize_dao<X,Y>(sender:&signer) {
        let storage = DaoAdmin<X, Y> { coin_x: coin::zero<X>(), coin_y: coin::zero<Y>() };
        move_to(sender, storage);

        let events_store = DaoEventsStore<X, Y> {
            register_dao_handle: account::new_event_handle(sender),
            add_dao_handle: account::new_event_handle(sender),
            withdraw_dao_handle: account::new_event_handle(sender)
        };
        event::emit_event(
            &mut events_store.register_dao_handle,
            DaoRegisterEvent<X, Y> {}
        );
        move_to(sender, events_store);
    }

    public(friend) fun add_dao<X,Y>(
        pool_addr: address,
        coin_x:Coin<X>,
        coin_y:Coin<Y>
    ) acquires DaoAdmin, DaoEventsStore {
        let x_val = coin::value(&coin_x);
        let y_val = coin::value(&coin_y);
        let storage = borrow_global_mut<DaoAdmin<X, Y>>(pool_addr);
        coin::merge(&mut storage.coin_x, coin_x);
        coin::merge(&mut storage.coin_y, coin_y);

        let events_store = borrow_global_mut<DaoEventsStore<X, Y>>(pool_addr);
        event::emit_event(
            &mut events_store.add_dao_handle,
            DaoAddEvent<X, Y> { x_val, y_val }
        );
    }

    public fun withdraw_dao<X,Y>(
        dao_admin:&signer,
        pool_addr: address,
        x_val:u64,
        y_val:u64,
    ) :(Coin<X>, Coin<Y>) acquires DaoAdmin, DaoEventsStore  {
        assert!(signer::address_of(dao_admin) == global_config::get_dao_admin(),ERR_NOT_PERMITTED);

        let storage = borrow_global_mut<DaoAdmin<X, Y>>(pool_addr);
        let coin_x = coin::extract(&mut storage.coin_x, x_val);
        let coin_y = coin::extract(&mut storage.coin_y, y_val);

        let events_store = borrow_global_mut<DaoEventsStore<X, Y>>(pool_addr);
        event::emit_event(
            &mut events_store.withdraw_dao_handle,
            DaoRemoveEvent<X, Y> { x_val, y_val }
        );

        (coin_x, coin_y)
    }
}