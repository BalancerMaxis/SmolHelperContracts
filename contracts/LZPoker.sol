// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";
import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";



// See: https://github.com/witherblock/gyarados/blob/main/contracts/CrossChainRateProvider.sol
interface ICrossChainRateProvider {
    function updateRate() external payable;
}

/**
 * @title The LZRateProviderPoker Contract
 * @author tritium.eth
 * @notice This is a simple contract to hold some eth and a list of LayerZeroRateProviders that need to be poked on mainnet
 * @notice When called by a set keeper, it uses it's internal eth balance to call updateRate() on all the listed providers.
 * @notice The contract includes the ability to withdraw eth and sweep all ERC20 to the owner address (owner only)
 * see https://github.com/witherblock/gyarados/blob/main/contracts/CrossChainRateProvider.sol
 */
contract LZRateProviderPoker is ConfirmedOwner, Pausable, KeeperCompatibleInterface {
    using EnumerableSet for EnumerableSet.AddressSet;
    event poked(address[] gaugelist, uint256 cost);


    event wrongCaller(address sender, address registry);
    event minWaitPeriodUpdated(uint256 minWaitSeconds);
    event gasTokenWithdrawn(uint256 amount, address recipient);
    event ERC20Swept(address token, address recipient, uint256 amount);
    event rateProviderAdded(address rateProvider);
    event rateProviderAlreadyExists(address rateProvider);
    event KeeperAddressUpdated(address oldAddress, address newAddress);
    event rateProviderRemove(address rateProvider);
    event removeNonexistentRateProvider(address rateProvider);
    event pokeFailed(address rateProvider);

    error OnlyKeeperRegistry(address sender);



    address public KeeperAddress;
    EnumerableSet.AddressSet private LZRateProviders;
    uint256 public MinWaitPeriodSeconds;
    uint256 public LastRun;

     /**
   * @param minWaitPeriodSeconds The minimum wait period for address between funding (for security)
   */
    constructor(uint256 minWaitPeriodSeconds)
    ConfirmedOwner(msg.sender) {
        setMinWaitPeriodSeconds(minWaitPeriodSeconds);
    }

      /**
   * @notice Check if enough time has passed and if so return true and a list of rate providers to poke based on the
   * @notice current contents of LZRateProviders.  This is done to save gas from getting EnumerableSet values on execution.
   * @return upkeepNeeded signals if upkeep is needed, performData is an abi encoded list of addresses to poke
   */
  function checkUpkeep(bytes calldata) external view override whenNotPaused
  returns (bool upkeepNeeded, bytes memory performData){
      if (
          LastRun + MinWaitPeriodSeconds <= block.timestamp
      ) {
          return (true, abi.encode(getRateProviders()));
      } else {
          return (false, abi.encode(new address[](0)));
      }
  }

    function performUpkeep(bytes calldata performData) external override  whenNotPaused {
        address[] memory toPoke = abi.decode(performData, (address[]));
        pokeList(toPoke);
  }

     /**
   * @notice Calls updateRate() on a list of LZ Rate Providers
   */
    function pokeList(address[] memory rateProviders) internal whenNotPaused {
        for (uint i=0; i<rateProviders.length; i++){
            try ICrossChainRateProvider(rateProviders[i]).updateRate(){
                // do we need an event here
            }
            catch {
                emit pokeFailed(rateProviders[i]);
            }
        }
    }

    function addRateProvider (address rateProvider) public onlyOwner {
        if(LZRateProviders.add(rateProvider)) {
            emit rateProviderAdded(rateProvider);
        } else {
            emit rateProviderAlreadyExists(rateProvider);
        }
    }

    function addRateProviders (address[] memory rateProviders) public onlyOwner {
        for(uint i=0; i<rateProviders.length; i++){
             if(LZRateProviders.add(rateProviders[i])) {
                 emit rateProviderAdded(rateProviders[i]);
             } else {
                 emit rateProviderAlreadyExists(rateProviders[i]);
             }
        }
    }
    function removeRateProvider(address rateProvider) public onlyOwner {
        if(LZRateProviders.remove(rateProvider)){
            emit rateProviderRemove(rateProvider);
        } else {
            emit removeNonexistentRateProvider(rateProvider);
        }
    }

    function removeRateProviders(address[] memory rateProviders) public onlyOwner {
        for(uint i=0; i<rateProviders.length; i++){
            if(LZRateProviders.remove(rateProviders[i])){
                emit rateProviderRemove(rateProviders[i]);
            } else {
                emit removeNonexistentRateProvider(rateProviders[i]);
            }
        }
    }


    function getRateProviders() public view returns (address[] memory) {
        return LZRateProviders.values();
    }


    /**
     * @notice Withdraws the contract balance back to the owner
   * @param amount The amount of eth (in wei) to withdraw
   */
    function withdrawGasToken(uint256 amount) external onlyOwner {
        emit gasTokenWithdrawn(amount, owner());
        Address.sendValue(payable(owner()), amount);
    }

    /**
     * @notice Sweep the full contract's balance for a given ERC-20 token back to the owner
   * @param token The ERC-20 token which needs to be swept
   */
    function sweep(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        emit ERC20Swept(token, owner(), balance);
        SafeERC20.safeTransfer(IERC20(token), owner(), balance);
    }

    /**
     * @notice Sets the keeper registry address
   */
    function setKeeperAddress(address keeperAddress) public onlyOwner {
        emit KeeperAddressUpdated(KeeperAddress, keeperAddress);
        KeeperAddress = keeperAddress;
    }

    /**
     * @notice Sets the minimum wait period (in seconds) for addresses between injections
   */
    function setMinWaitPeriodSeconds(uint256 minWaitSeconds) public onlyOwner {
        emit minWaitPeriodUpdated(MinWaitPeriodSeconds);
        MinWaitPeriodSeconds = minWaitSeconds;
    }

    /**
     * @notice Pauses the contract, which prevents executing performUpkeep
   */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract
   */
    function unpause() external onlyOwner {
        _unpause();
    }
}
