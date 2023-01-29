/// The `CoinHelper` module contains helper funcs to work with `AptosFramework::Coin` module.
module dev_account::util {
    use std::option; //Abstraction of a value that may or may not be present.
    use std::string::{Self, String};

    use aptos_framework::coin;
    use aptos_std::comparator::{Self, Result};
    use aptos_std::type_info;

    use dev_account::math;

    // Errors codes.

    /// When both coins have same names and can't be ordered.
    const ERR_CANNOT_BE_THE_SAME_COIN: u64 = 3000;

    /// When provided CoinType is not a coin.
    const ERR_IS_NOT_COIN: u64 = 3001;

    /// Length of symbol prefix to be used in LP coin symbol.
    const SYMBOL_PREFIX_LENGTH: u64 = 3002;

    /// Compare two coins, `X` and `Y`, using names.
    /// Caller should call this function to determine the order of X, Y.
    public fun compare<X, Y>(): Result {
        let x_info = type_info::type_of<X>(); // return xTypeInfo,struct{address,modula_name,struct_name}
        let y_info = type_info::type_of<Y>();

        // 1. compare struct name
        let x_struct_name = type_info::struct_name(&x_info); // return x struct name
        let y_struct_name = type_info::struct_name(&y_info);
        // return Result a struct,that includes u8;
        // u8 =0,euqal; u8=1, smaller; u8 =2, greater
        let struct_cmp = comparator::compare(&x_struct_name,&y_struct_name);
        // if not equal
        if (!comparator::is_equal(&struct_cmp)) return struct_cmp;

        //2. if struct name equals, compare module name
        let x_module_name = type_info::module_name(&x_info);
        let y_module_name = type_info::module_name(&y_info);
        let module_cmp = comparator::compare(&x_module_name,&y_module_name);
        if (!comparator::is_equal(&struct_cmp)) return module_cmp;

        //3. if module_name equal, compare address
        let x_address = type_info::module_name(&x_info);
        let y_address = type_info::module_name(&y_info);
        let address_cmp = comparator::compare(&x_address,&y_address);
        address_cmp
    }

    public fun sort_token_type<X,Y>() :bool{
        let order = compare<X,Y>();
        assert!(!comparator::is_equal(&order),ERR_CANNOT_BE_THE_SAME_COIN);
        comparator::is_smaller_than(&order)
    }

    public fun check_coin_initialized<CoinType>() {
        assert!(coin::is_coin_initialized<CoinType>(), ERR_IS_NOT_COIN);
    }

    public fun supply<CoinType>(): u128 {
        //Convert a 'some' option to a none by removing and returning the value stored inside t Aborts if t does not hold a value
        option::extract(&mut coin::supply<CoinType>())
    }

    public fun coin_symbol_prefix<CoinType>(): String {
        let symbol = coin::symbol<CoinType>();
        let prefix_length = math::min_u64(string::length(&symbol),SYMBOL_PREFIX_LENGTH);
        string::sub_string(&symbol,0,prefix_length)
    }

}