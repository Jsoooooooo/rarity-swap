module dev_account::router {
    use dev_account::util;
    use dev_account::init;
    use aptos_framework::coin;
    use dev_account::init::LPToken;
    use dev_account::math;
    use aptos_framework::coin::Coin;
    use std::signer::address_of;

    const ERR_SHOULD_BE_ORDERED:u64 = 0;
    const ERR_INSUFFICIENT_X_AMOUNT:u64=1;
    const ERR_INSUFFICIENT_Y_AMOUNT:u64=2;
    const ERR_WRONG_AMOUNT:u64=4;
    const ERR_OVERLIMIT:u64=5;
    const ERR_OUTPUT_LESS_THAN_EXPECTED:u64=6;
    const ERR_OVERLIMIT_X:u64=7;
    const ERR_INCORRECT:u64=8;
    const ERR_INSUFFICIENT_LIQUIDITY:u64 =9;
    const ERR_INSUFFICIENT_AMOUNT:u64 =10;
    const ERR_COIN_VAL_MAX_LESS_THAN_NEEDED:u64=11;
    const ERR_INSUFFICIENT_INPUT_AMOUNT:u64 = 12;

    public entry fun create_pair<X, Y>(sender: &signer) {
        if (util::sort_token_type<X, Y>()) {
            init::create_pair<X, Y>(sender);
        } else {
            init::create_pair<Y, X>(sender);
        }
    }

    public entry fun add_liquidity_entry<X,Y>(
        sender:&signer,
        amount_x_desired: u64,
        amount_y_desired: u64,
        min_x_amount_out: u64,
        min_y_amount_out: u64,
    ){
        if (!(init::is_pool_exist<X, Y>() || init::is_pool_exist<Y, X>())) {
            create_pair<X, Y>(sender);
        };

        assert!(util::sort_token_type<X, Y>(),ERR_SHOULD_BE_ORDERED);

        let (optimal_x, optimal_y) = get_optimal_price<X, Y>(
            amount_x_desired,
            amount_y_desired,
            min_x_amount_out,
            min_y_amount_out
        );
        let coin_x = coin::withdraw<X>(sender, optimal_x);
        let coin_y = coin::withdraw<Y>(sender, optimal_y);

        let lp_amount = init::add_liquidity<X, Y>(coin_x,coin_y);

        let sender_addr = address_of(sender);
        if (!coin::is_account_registered<LPToken<X, Y>>(sender_addr)) {
            coin::register<LPToken<X, Y>>(sender);
        };
        coin::deposit(sender_addr, lp_amount);
    }

    /// Burn liquidity coins `LP` and get coins `X` and `Y` back.
    /// * `lp_coins` - `LP` coins to burn.
    /// * `min_x_out_val` - minimum amount of `X` coins must be out.
    /// * `min_y_out_val` - minimum amount of `Y` coins must be out.

    public entry fun remove_liquidity_entry<X, Y>(
        sender:&signer,
        liquidity:u64,
        min_x_amount_out: u64,
        min_y_amount_out: u64,
    ){
        assert!(util::sort_token_type<X, Y>(), ERR_SHOULD_BE_ORDERED);
        // withdraw lp_amount from account
        let lp_coins = coin::withdraw<LPToken<X, Y>>(sender, liquidity);

        let (amount_x, amount_y) = init::remove_liquidity<X, Y>(lp_coins);

        assert!(coin::value(&amount_x) >= min_x_amount_out, ERR_OUTPUT_LESS_THAN_EXPECTED);
        assert!(coin::value(&amount_y) >= min_y_amount_out,ERR_OUTPUT_LESS_THAN_EXPECTED);

        let sender_addr = address_of(sender);
        // transfer tokens to sender
        coin::deposit(sender_addr, amount_x);
        coin::deposit(sender_addr, amount_y);
    }

    /// amount_in - amount put in
    /// min_amount_out -- required minimum return
    public entry fun swap_exact_x_for_y_entry<X, Y>(
        sender: &signer,
        amount_in: u64,
        min_amount_out: u64,
    ) {
        let coin_in = coin::withdraw<X>(sender, amount_in);
        let coin_in_val = coin::value(&coin_in);
        let coin_out_val = get_amount_out<X, Y>(coin_in_val);

        assert!(coin_out_val >= min_amount_out, ERR_OUTPUT_LESS_THAN_EXPECTED, );

        let coin_out = execute_swap<X, Y>(coin_in, coin_out_val);
        coin::deposit<Y>(address_of(sender), coin_out);
    }

    /// amount_in_max: max_amount for swapping exact y amount
    /// amount_out: required return amount
    public entry fun swap_x_for_exact_y_entry<X, Y>(
        sender:&signer,
        amount_in_max: u64,
        amount_out_required: u64,
    ){
        let amount_in_needed = get_amount_in<X, Y>(amount_out_required);
        // withdraw exact needed amount from signer
        let coin_in = coin::withdraw<X>(sender, amount_in_needed);
        assert!(amount_in_needed <= amount_in_max, ERR_COIN_VAL_MAX_LESS_THAN_NEEDED);

        let coin_out = execute_swap<X, Y>(coin_in, amount_out_required);

        coin::deposit<Y>(address_of(sender), coin_out);
    }

    /// amount out -- required amount out
    fun execute_swap<X, Y>(
        coin_in: Coin<X>,
        amount_out: u64,
    ): Coin<Y> {
        let (zero, coin_out);
        if (util::sort_token_type<X, Y>()) {
            (zero, coin_out) = init::swap<X, Y>(coin_in, 0, coin::zero(), amount_out);
        } else {
            (coin_out, zero) = init::swap<Y, X>(coin::zero(), amount_out, coin_in, 0);
        };
        coin::destroy_zero(zero);

        coin_out
    }

    /// multiple exact coin for coin move-swap
    fun swap_exact_x_for_y_multiple_helper<X, Y>(
        coin_in: Coin<X>,
    ) :Coin<Y> {
        let coin_in_val = coin::value(&coin_in);
        let coin_out_val = get_amount_out<X, Y>(coin_in_val);

        let coin_out = execute_swap<X, Y>(coin_in, coin_out_val);
        coin_out
    }

    public entry fun swap_exact_intput_double_entry<X,Y,Z>(
        account: &signer,
        amount_in: u64,
        amount_out_min: u64,
    ){
        let coin_x = coin::withdraw<X>(account,amount_in);
        let mid_coin = swap_exact_x_for_y_multiple_helper<X,Y>(coin_x);
        let final_coin = swap_exact_x_for_y_multiple_helper<Y,Z>(mid_coin);

        let final_coin_amount = coin::value(&final_coin);
        assert!(final_coin_amount >= amount_out_min,ERR_OUTPUT_LESS_THAN_EXPECTED);

        let account_addr = address_of(account);
        coin::deposit(account_addr,final_coin);
    }

    public entry fun swap_exact_intput_triple_entry<X,Y,Z,A>(
        account: &signer,
        amount_in: u64,
        amount_out_min: u64,
    ){
        let coin_x = coin::withdraw<X>(account,amount_in);
        let y_coin = swap_exact_x_for_y_multiple_helper<X,Y>(coin_x);
        let z_coin = swap_exact_x_for_y_multiple_helper<Y,Z>(y_coin);
        let final_coin = swap_exact_x_for_y_multiple_helper<Z,A>(z_coin);
        let final_coin_amount = coin::value(&final_coin);
        assert!(final_coin_amount >= amount_out_min,ERR_OUTPUT_LESS_THAN_EXPECTED);

        let account_addr = address_of(account);
        coin::deposit(account_addr,final_coin);
    }

    /// multiple coin for exact coin move-swap
    fun swap_x_for_exact_y_multiple_helper<X,Y,Z>(
        amount_out_required:u64,
    ) :(u64,u64) {
        let y_needed = get_amount_in<Y, Z>(amount_out_required);
        let x_needed = get_amount_in<X, Y>(y_needed);
        (y_needed,x_needed)
    }

    public entry fun swap_x_for_exact_y_double_entry<X, Y,Z>(
        sender:&signer,
        amount_in_max: u64,
        amount_out_required: u64,
    ){
        let (y_needed,x_needed)  = swap_x_for_exact_y_multiple_helper<X, Y,Z>(amount_out_required);
        let coin_in = coin::withdraw<X>(sender, x_needed);

        assert!(x_needed <= amount_in_max, ERR_COIN_VAL_MAX_LESS_THAN_NEEDED);

        let y_coin = execute_swap<X, Y>(coin_in, x_needed);
        let z_coin = execute_swap<Y, Z>(y_coin, y_needed);
        coin::deposit<Z>(address_of(sender), z_coin);
    }
    /// Get current cumulative prices in liquidity pool `X`/`Y`.
    /// Returns (X price, Y price, block_timestamp).
    public fun get_cumulative_prices<X, Y>(): (u128, u128, u64) {
        if (util::sort_token_type<X, Y>()) {
            init::get_current_price<X, Y>()
        } else {
            let (y, x, t) = init::get_current_price<Y, X>();
            (x, y, t)
        }
    }

    /// Get reserves of liquidity pool (`X` and `Y`).
    /// Returns current reserves (`X`, `Y`).
    public fun get_reserves_size<X, Y>(): (u64, u64) {
        if (util::sort_token_type<X, Y>()) {
            init::get_reserves<X, Y>()
        } else {
            let (y_res, x_res) = init::get_reserves<Y, X>();
            (x_res, y_res)
        }
    }

    /// Get fee for specific pool together with denominator (numerator, denominator).
    public fun get_fees_config<X, Y>(): (u64, u64) {
        if (util::sort_token_type<X, Y>()) {
            init::get_fees_config<X, Y>()
        } else {
            init::get_fees_config<Y, X>()
        }
    }

    /// Get DAO fee for specific pool together with denominator (numerator, denominator).
    public fun get_dao_fees_config<X, Y>(): (u64, u64) {
        if (util::sort_token_type<X, Y>()) {
            init::get_dao_config<X, Y>()
        } else {
            init::get_dao_config<Y, X>()
        }
    }

    /// Check move-swap for pair `X` and `Y` exists.
    /// If pool exists returns true, otherwise false.
    public fun is_swap_exists<X, Y>(): bool {
        if (util::sort_token_type<X, Y>()) {
            init::is_pool_exist<X, Y>()
        } else {
            init::is_pool_exist<Y, X>()
        }
    }

    fun get_optimal_price<X,Y>(
        added_x:u64,
        added_y:u64,
        x_min:u64,
        y_min:u64,
    ) :(u64,u64){
        let (reserve_x,reserve_y) = get_reserves_size<X,Y>();

        let (a_x, a_y) = if (reserve_x == 0 && reserve_y == 0) {
            (added_x, added_y)
        } else {
            let amount_y_optimal = quote(added_x, reserve_x, reserve_y);
            if (amount_y_optimal <= added_y) {
                assert!(amount_y_optimal >= y_min,ERR_INSUFFICIENT_Y_AMOUNT);
                (added_x, amount_y_optimal)
            } else {
                let amount_x_optimal = quote(added_y, reserve_y, reserve_x);
                assert!(amount_x_optimal <= added_x, ERR_INCORRECT);
                assert!(amount_x_optimal >= x_min, ERR_INSUFFICIENT_X_AMOUNT);
                (amount_x_optimal, added_y)
            }
        };
        (a_x,a_y)
    }

    public fun quote(amount_x: u64, reserve_x: u64, reserve_y: u64): u64 {
        assert!(amount_x > 0, ERR_INSUFFICIENT_AMOUNT);
        assert!(reserve_x > 0 && reserve_y > 0, ERR_INSUFFICIENT_LIQUIDITY);
        (((amount_x as u128) * (reserve_y as u128) / (reserve_x as u128)) as u64)
    }

    public fun get_amount_in<X, Y>(amount_out: u64): u64 {
        let (reserve_in, reserve_out) = get_reserves_size<X, Y>();
        let (fee_pct, fee_scale) = get_fees_config<X, Y>();
        let fee_multiplier = fee_scale - fee_pct;

        let new_reserves_out = (reserve_out - amount_out) * fee_multiplier;

        // coin_out * reserve_in * fee_scale / new reserves out
        let coin_in = math::mul_div(amount_out, reserve_in * fee_scale, new_reserves_out) + 1;
        coin_in
    }

    public fun get_amount_out<X, Y>(
        amount_in: u64,
    ): u64 {
        let (reserve_in, reserve_out) = get_reserves_size<X, Y>();
        assert!(amount_in > 0, ERR_INSUFFICIENT_INPUT_AMOUNT);
        assert!(reserve_in > 0 && reserve_out > 0, ERR_INSUFFICIENT_LIQUIDITY);

        let (fee_pct, fee_scale) = get_fees_config<X, Y>();

        let coin_in_val_after_fees = amount_in * (fee_scale - fee_pct);
        let new_reserve_in = reserve_in * fee_scale + coin_in_val_after_fees;

        math::mul_div(coin_in_val_after_fees, reserve_out, new_reserve_in)
    }

    public fun get_reserves_for_lp_coins<X, Y, Curve>(
        lp_to_burn_val: u64
    ): (u64, u64) {
        let (x_reserve, y_reserve) = get_reserves_size<X, Y>();
        let lp_coins_total = util::supply<LPToken<X, Y>>();

        let x_to_return_val = math::mul_div_u128((lp_to_burn_val as u128), (x_reserve as u128), lp_coins_total);
        let y_to_return_val = math::mul_div_u128((lp_to_burn_val as u128), (y_reserve as u128), lp_coins_total);

        assert!(x_to_return_val > 0 && y_to_return_val > 0, ERR_WRONG_AMOUNT);

        (x_to_return_val, y_to_return_val)
    }
}