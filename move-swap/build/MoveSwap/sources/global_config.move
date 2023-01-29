module dev_account::global_config{
    use aptos_std::event::{Self,EventHandle};
    use aptos_framework::account;

    use std::signer::address_of;

    friend dev_account::init;

      /// When config doesn't exists.
    const ERR_CONFIG_NOT_EXIST: u64 = 400;
    /// Not permitted to create config
    const ERR_NOT_PERMITTED: u64 = 401;
    /// When user is not admin
    const ERR_NOT_ADMIN: u64 = 402;
    /// When invalid fee amount
    const ERR_INVALID_FEE: u64 = 403;

    /// Minimum value of fee, 0.01%
    const MIN_FEE: u64 = 1;

    /// Maximum value of fee, 1%
    const MAX_FEE: u64 = 100;

    /// Minimum value of dao fee, 0%
    const MIN_DAO_FEE: u64 = 0;

    /// Maximum value of dao fee, 100%
    const MAX_DAO_FEE: u64 = 100;

      /// The global configuration (fees and admin accounts).
    struct GlobalConfig has key {
        dao_admin_address: address,
        fee_admin_address: address,
        default_fee:u64,
        default_dao_fee: u64,
    }

    struct EventStore has key {
        default_unstable_fee_event: EventHandle<UpdateFeeEvent>,
        default_stable_fee_event: EventHandle<UpdateFeeEvent>,
        default_dao_fee_event: EventHandle<UpdateFeeEvent>,
    }

    struct UpdateFeeEvent has drop, store {
        fee: u64,
    }

    public fun initialize(
        swap_owner:&signer
    ){
        assert!(address_of(swap_owner) == @dev_account,ERR_NOT_PERMITTED);

        move_to(swap_owner,GlobalConfig {
            dao_admin_address:@dao_admin,
            fee_admin_address:@fee_admin,
            default_fee: 20, // 0.2%
            default_dao_fee:25, //25%
        });

        move_to(swap_owner,EventStore{
            default_unstable_fee_event:account::new_event_handle(swap_owner),
            default_stable_fee_event:account::new_event_handle(swap_owner),
            default_dao_fee_event:account::new_event_handle(swap_owner),
        });
    }

    public fun get_dao_admin() :address acquires GlobalConfig{
        assert!(exists<GlobalConfig>(@dev_account),ERR_CONFIG_NOT_EXIST);

        let config = borrow_global<GlobalConfig>(@dev_account);
        config.dao_admin_address
    }

    public fun get_fee_admin(): address acquires GlobalConfig {
        assert!(exists<GlobalConfig>(@dev_account),ERR_CONFIG_NOT_EXIST);

        let config =borrow_global<GlobalConfig>(@dev_account);
        config.fee_admin_address
    }

    public fun set_dao_admin(
        admin:&signer,
        new_address:address
    ) acquires GlobalConfig {
        assert!(exists<GlobalConfig>(@dao_admin),ERR_CONFIG_NOT_EXIST);
        let config = borrow_global_mut<GlobalConfig>(@dao_admin);
        assert!(config.dao_admin_address == address_of(admin),ERR_NOT_PERMITTED);
        config.dao_admin_address = new_address
    }

    public fun set_fee_admin(
        admin:&signer,
        new_address:address
    ) acquires GlobalConfig {
        assert!(exists<GlobalConfig>(@dev_account),ERR_CONFIG_NOT_EXIST);
        let config = borrow_global_mut<GlobalConfig>(@dev_account);
        assert!(config.fee_admin_address == address_of(admin),ERR_NOT_PERMITTED);
        config.fee_admin_address = new_address
    }

    public fun get_dao_fee():u64 acquires GlobalConfig{
        assert!(exists<GlobalConfig>(@dev_account),ERR_CONFIG_NOT_EXIST);

        let config = borrow_global<GlobalConfig>(@dev_account);
        config.default_dao_fee
    }

    public fun set_dao_fee(
        admin:&signer,
        new_fee:u64
    ) acquires GlobalConfig,EventStore{
        assert!(exists<GlobalConfig>(@dev_account),ERR_CONFIG_NOT_EXIST);
        let config = borrow_global_mut<GlobalConfig>(@dev_account);
        assert!(config.fee_admin_address==address_of(admin),ERR_NOT_PERMITTED);
        assert_valid_dao_fee(new_fee);

        config.default_dao_fee = new_fee;
        let events = borrow_global_mut<EventStore>(@dev_account);
        event::emit_event(
            &mut events.default_dao_fee_event,
            UpdateFeeEvent { fee: new_fee }
        );
    }

    public fun get_fee():u64 acquires GlobalConfig{
        assert!(exists<GlobalConfig>(@dev_account),ERR_CONFIG_NOT_EXIST);
        let config = borrow_global<GlobalConfig>(@dev_account);
        config.default_fee
    }

    public fun set_fee(
        admin:&signer,
        new_fee:u64
    ) acquires GlobalConfig,EventStore {
        assert!(exists<GlobalConfig>(@dev_account), ERR_CONFIG_NOT_EXIST);

        let config = borrow_global_mut<GlobalConfig>(@dev_account);
        assert!(config.fee_admin_address == address_of(admin),ERR_NOT_PERMITTED);
        assert_valid_fee(new_fee);

        let events = borrow_global_mut<EventStore>(@dev_account);

        config.default_fee = new_fee;
        event::emit_event(
            &mut events.default_unstable_fee_event,
            UpdateFeeEvent { fee: new_fee }
        );
    }

    public fun assert_valid_dao_fee(dao_fee: u64) {
        assert!(MIN_DAO_FEE <= dao_fee && dao_fee <= MAX_DAO_FEE, ERR_INVALID_FEE);
    }

    public fun assert_valid_fee(fee: u64) {
        assert!(MIN_FEE <= fee && fee <= MAX_FEE, ERR_INVALID_FEE);
    }
}