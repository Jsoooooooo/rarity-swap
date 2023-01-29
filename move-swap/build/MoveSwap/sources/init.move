module dev_account::init {
    use std::signer;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::timestamp;
    use u256::u256;
    use uq64x64::uq64x64;
    use dev_account::util;
    use dev_account::global_config;
    use dev_account::math;
    use std::string;
    use std::signer::address_of;
    use dev_account::events;
    use dev_account::dao;
    use aptos_framework::resource_account;

    /// When coins used to create pair have wrong ordering.
    const ERR_WRONG_PAIR_ORDERING: u64 = 100;

    /// When pair already exists on account.
    const ERR_POOL_EXISTS_FOR_PAIR: u64 = 101;

    /// When not enough liquidity minted.
    const ERR_NOT_ENOUGH_INITIAL_LIQUIDITY: u64 = 102;

    /// When not enough liquidity minted.
    const ERR_NOT_ENOUGH_LIQUIDITY: u64 = 103;

    /// When both X and Y provided for move-swap are equal zero.
    const ERR_EMPTY_COIN_IN: u64 = 104;

    /// When incorrect INs/OUTs arguments passed during move-swap and math doesn't work.
    const ERR_INCORRECT_SWAP: u64 = 105;

    /// Incorrect lp coin burn values
    const ERR_INCORRECT_BURN_VALUES: u64 = 106;

    /// When pool doesn't exists for pair.
    const ERR_POOL_DOES_NOT_EXIST: u64 = 107;

    /// Should never occur.
    const ERR_UNREACHABLE: u64 = 108;

    /// When `initialize()` transaction is signed with any account other than @liquidswap.
    const ERR_NOT_ENOUGH_PERMISSIONS_TO_INITIALIZE: u64 = 109;


    /// When pool is locked.
    const ERR_POOL_IS_LOCKED: u64 = 111;

    /// When user is not admin
    const ERR_NOT_ADMIN: u64 = 112;

    const ERR_COIN_OUT_NUM_LESS_THAN_EXPECTED:u64=113;


      /// Minimal liquidity.
    const MINIMAL_LIQUIDITY: u64 = 1000;
    const ERR_INCORRECT:u64=1001;

    /// Denominator to handle decimal points for fees.
    const FEE_SCALE: u64 = 10000;
    const DAO_FEE_SCALE: u64 = 100;

    struct PoolAccountCapability has key {
        signer_cap: SignerCapability
    }
    struct LPToken<phantom X, phantom Y> {}

    struct TokenMeta<phantom X, phantom Y> has key {
        creator:address,
        balance_x: Coin<X>,
        balance_y: Coin<Y>,
        lp_mint_cap: coin::MintCapability<LPToken<X, Y>>,
        lp_burn_cap: coin::BurnCapability<LPToken<X, Y>>,
        block_timestamp: u64,
        last_x_price: u128,
        last_y_price: u128,
        fee: u64,           // 1 - 100 (0.01% - 1%)
        dao_fee: u64,       // 0 - 100 (0% - 100%)
    }

    fun init_module(sender:&signer){
        let signer_cap = resource_account::retrieve_resource_account_cap(sender, @swap);
        let resource_signer = account::create_signer_with_capability(&signer_cap);
        move_to(&resource_signer, PoolAccountCapability { signer_cap });
        global_config::initialize(&resource_signer);
    }

    public fun create_pair<X, Y>(
        sender: &signer
    ) acquires PoolAccountCapability {
        util::check_coin_initialized<X>();
        util::check_coin_initialized<Y>();
        assert!(util::sort_token_type<X, Y>(), ERR_WRONG_PAIR_ORDERING);

        assert!(!exists<TokenMeta<X, Y>>(@dev_account), ERR_POOL_EXISTS_FOR_PAIR);
        let pool_cap = borrow_global<PoolAccountCapability>(@dev_account);
        let resource_signer = account::create_signer_with_capability(&pool_cap.signer_cap);

        let lp_name: string::String = string::utf8(b"MoveRarity-");
        let name_x = coin::symbol<X>();
        let name_y = coin::symbol<Y>();
        string::append(&mut lp_name,name_x);
        string::append_utf8(&mut lp_name,b"-");
        string::append(&mut lp_name,name_y);
        string::append_utf8(&mut lp_name,b"-LP");

        let (lp_burn_cap, lp_freeze_cap, lp_mint_cap) =
            coin::initialize<LPToken<X, Y>>(
                &resource_signer,
                lp_name,
                string::utf8(b"Move-LP"),
                8,
                true
            );
        coin::destroy_freeze_cap(lp_freeze_cap);

        let poolMeta = TokenMeta<X, Y> {
            creator: address_of(sender),
            balance_x: coin::zero<X>(),
            balance_y: coin::zero<Y>(),
            lp_mint_cap,
            lp_burn_cap,
            block_timestamp: 0,
            last_x_price: 0,
            last_y_price: 0,
            fee: global_config::get_fee(),
            dao_fee: global_config::get_dao_fee(),
        };

        dao::initialize_dao<X,Y>(&resource_signer);
        events::initialize_event<X,Y>(&resource_signer);
        move_to(&resource_signer, poolMeta);
    }


    /// optimal_coin_x -- optimal amount the calculated on router.move
    /// optimal_coin_x -- optimal amount the calculated on router.move
    public fun add_liquidity<X, Y>(
        optimal_coin_x: Coin<X>,
        optimal_coin_y: Coin<Y>,
    ) :Coin<LPToken<X,Y>> acquires TokenMeta{
        assert!(exists<TokenMeta<X, Y>>(@dev_account), ERR_POOL_DOES_NOT_EXIST);

        let pool = borrow_global_mut<TokenMeta<X,Y>>(@dev_account);
        let pool_reserve_x = coin::value(&pool.balance_x);
        let pool_reserve_y = coin::value(&pool.balance_y);

        let lp_coins_total = util::supply<LPToken<X, Y>>();

        let amount_x = coin::value<X>(&optimal_coin_x);
        let amount_y = coin::value<Y>(&optimal_coin_y);

        let provided_liq = if (lp_coins_total == 0) {
            let initial_liq = math::sqrt(math::mul_to_u128(amount_x, amount_y));
            assert!(initial_liq > MINIMAL_LIQUIDITY, ERR_NOT_ENOUGH_INITIAL_LIQUIDITY);
            initial_liq - MINIMAL_LIQUIDITY
        } else {
            let x_liq = math::mul_div_u128((amount_x as u128), lp_coins_total, (pool_reserve_x as u128));
            let y_liq = math::mul_div_u128((amount_y as u128), lp_coins_total, (pool_reserve_y as u128));
            if (x_liq < y_liq) {
                x_liq
            } else {
                y_liq
            }
        };
        assert!(provided_liq > 0, ERR_NOT_ENOUGH_LIQUIDITY);
        //
        coin::merge(&mut pool.balance_x, optimal_coin_x);
        coin::merge(&mut pool.balance_y, optimal_coin_y);
        // // mint lp token as receipt
        let lp_coins = coin::mint<LPToken<X, Y>>(provided_liq, &pool.lp_mint_cap);

        update<X, Y>(pool, pool_reserve_x, pool_reserve_y);

        events::added_event<X,Y>(
            amount_x,
            amount_y,
            provided_liq
        );
        lp_coins
    }

    /// remove Liquidity
    public fun remove_liquidity<X,Y>(
        lp_coins: Coin<LPToken<X, Y>>
    ) :(Coin<X>, Coin<Y>) acquires TokenMeta{
        assert!(util::sort_token_type<X, Y>(), ERR_WRONG_PAIR_ORDERING);
        assert!(exists<TokenMeta<X, Y>>(@dev_account), ERR_POOL_DOES_NOT_EXIST);

        let pool = borrow_global_mut<TokenMeta<X,Y>>(@dev_account);
        let lp_coins_burning_val = coin::value(&lp_coins);

        let lp_coins_total = util::supply<LPToken<X, Y>>();
        let x_reserve_val = coin::value(&pool.balance_x);
        let y_reserve_val = coin::value(&pool.balance_y);

        let x_to_return_val = math::mul_div_u128((lp_coins_burning_val as u128), (x_reserve_val as u128), lp_coins_total);
        let y_to_return_val = math::mul_div_u128((lp_coins_burning_val as u128), (y_reserve_val as u128), lp_coins_total);
        assert!(x_to_return_val > 0 && y_to_return_val > 0, ERR_INCORRECT_BURN_VALUES);

        // take x_to_return_val and y_to_return_val out of pool
        let x_coin_to_return = coin::extract(&mut pool.balance_x, x_to_return_val);
        let y_coin_to_return = coin::extract(&mut pool.balance_y, y_to_return_val);

        update<X, Y>(pool, x_reserve_val, y_reserve_val);
        coin::burn(lp_coins, &pool.lp_burn_cap);

        (x_coin_to_return, y_coin_to_return)
    }

    /// * `x_in` - X coins to move-swap.
    /// * `x_out` - expected amount of X coins to get out.
    /// * `y_in` - Y coins to move-swap.
    /// * `y_out` - expected amount of Y coins to get out.
    public fun swap<X, Y>(
        x_in:Coin<X>,
        x_out:u64,
        y_in:Coin<Y>,
        y_out:u64
    ):(Coin<X>,Coin<Y>) acquires TokenMeta{
        assert!(util::sort_token_type<X, Y>(), ERR_WRONG_PAIR_ORDERING);
        assert!(exists<TokenMeta<X, Y>>(@dev_account), ERR_POOL_DOES_NOT_EXIST);

        let x_in_val = coin::value(&x_in);
        let y_in_val = coin::value(&y_in);

        assert!(x_in_val > 0 || y_in_val > 0, ERR_EMPTY_COIN_IN);

        let pool = borrow_global_mut<TokenMeta<X, Y>>(@dev_account);
        let x_reserve_size = coin::value(&pool.balance_x);
        let y_reserve_size = coin::value(&pool.balance_y);

        // Deposit new coins to liquidity pool.
        coin::merge(&mut pool.balance_x, x_in);
        coin::merge(&mut pool.balance_y, y_in);

        // Withdraw expected amount from reserves.
        let x_swapped = coin::extract(&mut pool.balance_x, x_out);
        let y_swapped = coin::extract(&mut pool.balance_y, y_out);

        let (x_res_new_after_fee, y_res_new_after_fee) =
            reserves_after_fees(
                coin::value(&pool.balance_x),
                coin::value(&pool.balance_y),
                x_in_val,
                y_in_val,
                pool.fee
            );
        assert_swap_correct(
            (x_reserve_size as u128),
            (y_reserve_size as u128),
            (x_res_new_after_fee as u128),
            (y_res_new_after_fee as u128),
        );

        inject_dao_fee(pool,x_in_val,y_in_val);
        update<X, Y>(pool, x_reserve_size, y_reserve_size);
        events::swap_event<X,Y>(
            x_in_val,
            y_in_val,
            x_out,
            y_out
        );

        // Return swapped amount.
        (x_swapped, y_swapped)
    }

    fun reserves_after_fees(
        reserve_x:u64,
        reserve_y:u64,
        x_in:u64,
        y_in:u64,
        fee:u64
    ) :(u128,u128) {
        let x_after_fee = math::mul_to_u128(reserve_x, FEE_SCALE) - math::mul_to_u128(x_in, fee);
        let y_after_fee = math::mul_to_u128(reserve_y, FEE_SCALE) - math::mul_to_u128(y_in, fee);
        (x_after_fee,y_after_fee)
    }

    fun inject_dao_fee<X,Y>(
        pool: &mut TokenMeta<X, Y>,
        x_in_val: u64,
        y_in_val: u64
    ){
        let dao_fee = pool.dao_fee;
        let fee_multiplier = pool.fee;

        let dao_fee_multiplier = fee_multiplier * dao_fee / DAO_FEE_SCALE;
        let dao_x_fee_val = math::mul_div(x_in_val, dao_fee_multiplier, FEE_SCALE);
        let dao_y_fee_val = math::mul_div(y_in_val, dao_fee_multiplier, FEE_SCALE);

        let dao_x_in = coin::extract(&mut pool.balance_x, dao_x_fee_val);
        let dao_y_in = coin::extract(&mut pool.balance_y, dao_y_fee_val);
        dao::add_dao<X, Y>(@dev_account, dao_x_in, dao_y_in);
    }


    fun assert_swap_correct(
        x_res: u128,
        y_res: u128,
        x_res_with_fees: u128,
        y_res_with_fees: u128,
    ) {
        let lp_value_before_swap = x_res * y_res;
        let lp_value_before_swap_u256 = u256::mul(
            u256::from_u128(lp_value_before_swap),
            u256::from_u64(FEE_SCALE * FEE_SCALE)
        );
        let lp_value_after_swap_and_fee = u256::mul(
            u256::from_u128(x_res_with_fees),
            u256::from_u128(y_res_with_fees),
        );

        let cmp = u256::compare(&lp_value_after_swap_and_fee, &lp_value_before_swap_u256);
        assert!(cmp == 2, ERR_INCORRECT_SWAP);
    }

    fun update<X,Y>(
        pool: &mut TokenMeta<X, Y>,
        x_reserve:u64,
        y_reserve: u64,
    ){
        let last_block_timestamp = pool.block_timestamp;

        let block_timestamp = timestamp::now_seconds();

        let time_elapsed = ((block_timestamp - last_block_timestamp) as u128);
        if (time_elapsed > 0 && x_reserve != 0 && y_reserve != 0) {
            let last_price_x_cumulative = uq64x64::to_u128(uq64x64::fraction(y_reserve, x_reserve)) * time_elapsed;
            let last_price_y_cumulative = uq64x64::to_u128(uq64x64::fraction(x_reserve, y_reserve)) * time_elapsed;

            pool.last_x_price = math::overflow_add(pool.last_x_price, last_price_x_cumulative);
            pool.last_y_price = math::overflow_add(pool.last_y_price, last_price_y_cumulative);

            let x_price = pool.last_x_price;
            let y_price = pool.last_y_price;
            events::oracle_event<X,Y>(x_price,y_price);
         };
        pool.block_timestamp = block_timestamp;
    }

    public fun get_reserves<X,Y>():(u64,u64) acquires TokenMeta{
        assert!(exists<TokenMeta<X, Y>>(@dev_account), ERR_POOL_DOES_NOT_EXIST);
        assert!(util::sort_token_type<X,Y>(),ERR_WRONG_PAIR_ORDERING);
       let pool = borrow_global<TokenMeta<X,Y>>(@dev_account);
        (
            coin::value(&pool.balance_x),
            coin::value(&pool.balance_y)
        )
    }

    public fun get_current_price<X,Y>() :(u128,u128,u64) acquires TokenMeta{
        assert!(util::sort_token_type<X, Y>(), ERR_WRONG_PAIR_ORDERING);
        assert!(exists<TokenMeta<X, Y>>(@dev_account), ERR_POOL_DOES_NOT_EXIST);

        let pool = borrow_global<TokenMeta<X,Y>>(@dev_account);
        let last_x_price = *&pool.last_x_price;
        let last_y_price = *&pool.last_y_price;
        let last_block_timestamp = pool.block_timestamp;
        (last_x_price,last_y_price,last_block_timestamp)
    }

    public fun is_pool_exist<X,Y>() :bool{
        assert!(util::sort_token_type<X, Y>(), ERR_WRONG_PAIR_ORDERING);
        exists<TokenMeta<X,Y>>(@dev_account)
    }

    public fun get_fees_config<X, Y>(): (u64, u64) acquires TokenMeta {
        let pool = borrow_global<TokenMeta<X,Y>>(@dev_account);
        (pool.fee, FEE_SCALE)
    }

    public entry fun set_fee<X,Y>(
        fee_admin:&signer,
        fee:u64
    ) acquires TokenMeta{
        assert!(util::sort_token_type<X, Y>(), ERR_WRONG_PAIR_ORDERING);
        assert!(exists<TokenMeta<X, Y>>(@dev_account), ERR_POOL_DOES_NOT_EXIST);

        assert!(signer::address_of(fee_admin) == global_config::get_fee_admin(), ERR_NOT_ADMIN);

        let pool = borrow_global_mut<TokenMeta<X, Y>>(@dev_account);
        pool.fee = fee;
        events::set_fee_event<X,Y>(fee);
    }

    public fun get_dao_config<X,Y> ():(u64,u64) acquires TokenMeta{
        assert!(util::sort_token_type<X, Y>(), ERR_WRONG_PAIR_ORDERING);
        assert!(exists<TokenMeta<X, Y>>(@dev_account), ERR_POOL_DOES_NOT_EXIST);

        let pool = borrow_global<TokenMeta<X,Y>>(@dev_account);
        (pool.dao_fee, DAO_FEE_SCALE)
    }

    public entry fun set_dao_fee<X,Y>(
        dao_admin:&signer,
        dao_fee:u64
    ) acquires TokenMeta{
        assert!(util::sort_token_type<X, Y>(), ERR_WRONG_PAIR_ORDERING);
        assert!(exists<TokenMeta<X, Y>>(@dev_account), ERR_POOL_DOES_NOT_EXIST);

        assert!(signer::address_of(dao_admin) == global_config::get_fee_admin(), ERR_NOT_ADMIN);
        global_config::assert_valid_dao_fee(dao_fee);

        let pool = borrow_global_mut<TokenMeta<X, Y>>(@dev_account);
        pool.dao_fee = dao_fee;
    }

    #[test_only]
    public fun initialize(sender: &signer) {
        init_module(sender);
    }
}