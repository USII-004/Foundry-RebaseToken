// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";

import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";

import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";


import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";

import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract CrossChainTest is Test {
  address owner = makeAddr("owner");
  address user = makeAddr("user");
  uint256 SEND_VALUE = 1e5;

  uint256 sepoliaFork;
  uint256 arbSepoliaFork;

  CCIPLocalSimulatorFork ccipLocalSimulatorFork;

  RebaseToken sepoliaToken;
  RebaseToken arbSepoliaToken;

  Vault vault;

  RebaseTokenPool sepoliaPool;
  RebaseTokenPool arbSepoliaPool;

  Register.NetworkDetails sepoliaNetworkDetails;
  Register.NetworkDetails arbSepoliaNetworkDetails;

  TokenAdminRegistry tokenAdminRegistrySepolia;
  TokenAdminRegistry tokenAdminRegistryArbSepolia;

  RegistryModuleOwnerCustom registryModuleOwnerCustomSepolia;
  RegistryModuleOwnerCustom registryModuleOwnerCustomArbSepolia;

  function setUp() public {

    address[] memory allowlist = new address[](0);

    // set up the sepolia and arb-sepolia forks
    sepoliaFork = vm.createSelectFork("sepolia");
    arbSepoliaFork = vm.createFork("arb-sepolia");

    ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
    vm.makePersistent(address(ccipLocalSimulatorFork));

    // -------- 1. Deploy on Sepolia --------
    sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
    vm.startPrank(owner);
    sepoliaToken = new RebaseToken();
    console.log("source rebaseToken address:", address(sepoliaToken));
    sepoliaPool = new RebaseTokenPool(
      IERC20(address(sepoliaToken)),
      allowlist,                                                                                               
      sepoliaNetworkDetails.rmnProxyAddress,                                                                                                                                                                                              
      sepoliaNetworkDetails.routerAddress
    );
    // deploy to the vault
    vault = new Vault(IRebaseToken(address(sepoliaToken)));
    // add rewards to the vault
    vm.deal(address(vault), 1e18);
    // set pool of the token contract for permissions on sepolia
    sepoliaToken.grantMintAndBurnRole(address(sepoliaPool));
    sepoliaToken.grantMintAndBurnRole(address(vault));
    // claim role on sepolia
    registryModuleOwnerCustomSepolia = RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress);
    registryModuleOwnerCustomSepolia.registerAdminViaOwner(address(sepoliaToken));
    // accept role on sepolia
    tokenAdminRegistrySepolia = TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress);
    tokenAdminRegistrySepolia.acceptAdminRole(address(sepoliaToken));
    // Link token to pool in the token admin resistry on sepolia
    tokenAdminRegistrySepolia.setPool(address(sepoliaToken), address(sepoliaPool));
    vm.stopPrank();

    // -------- 2. Deploy on Arb-Sepolia --------
    vm.selectFork(arbSepoliaFork);
    vm.startPrank(owner);
    arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
    arbSepoliaToken = new RebaseToken();
    console.log("destination rebase token address:", address(arbSepoliaToken));
    // deploy the token pool on arb-sepolia
    arbSepoliaPool = new RebaseTokenPool(
      IERC20(address(arbSepoliaToken)),
      allowlist,
      arbSepoliaNetworkDetails.rmnProxyAddress,
      arbSepoliaNetworkDetails.routerAddress
    );
    // set pool of the token contract for permissions on arb-sepolia
    arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaPool));
    // claim role on arb-sepolia
    registryModuleOwnerCustomArbSepolia = RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress);
    registryModuleOwnerCustomArbSepolia.registerAdminViaOwner(address(arbSepoliaToken));
    // accept role on arb-sepolia
    tokenAdminRegistryArbSepolia = TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress);
    tokenAdminRegistryArbSepolia.acceptAdminRole(address(arbSepoliaToken));
    // Link token to pool in the token admin registry on arb-sepolia 
    tokenAdminRegistryArbSepolia.setPool(address(arbSepoliaToken), address(arbSepoliaPool));
    vm.stopPrank();

    // --------3. Configure cross-chain --------
    configureTokenPool(
      sepoliaFork,
      sepoliaPool,
      arbSepoliaNetworkDetails,
      arbSepoliaPool,
      IRebaseToken(address(arbSepoliaToken))
    );

    configureTokenPool(
      arbSepoliaFork,
      arbSepoliaPool,
      sepoliaNetworkDetails,
      sepoliaPool,
      IRebaseToken(address(sepoliaToken))
    );
  }


  function configureTokenPool(
    uint256 fork,
    TokenPool localPool,
    Register.NetworkDetails memory remoteNetworkDetails,
    TokenPool remotePool,
    IRebaseToken remoteTokenAddress
  ) public  {
    vm.selectFork(fork);
    vm.startPrank(owner);
    TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);
    bytes[] memory remotePoolAddresses = new bytes[](1);
    remotePoolAddresses[0] = abi.encode(address(remotePool));
    chainsToAdd[0] = TokenPool.ChainUpdate({
      remoteChainSelector: remoteNetworkDetails.chainSelector,
      allowed: true,
      remotePoolAddress: remotePoolAddresses[0],
      remoteTokenAddress: abi.encode(address(remoteTokenAddress)),
      outboundRateLimiterConfig: RateLimiter.Config({
        isEnabled: false,
        capacity: 0,
        rate: 0
      }),
      inboundRateLimiterConfig: RateLimiter.Config({
        isEnabled: false,
        capacity: 0,
        rate: 0
      })
    });
    localPool.applyChainUpdates(chainsToAdd);
    vm.stopPrank();
  }

  function bridgeTokens(
    uint256 amountToBridge,
    uint256 localFork,
    uint256 remoteFork,
    Register.NetworkDetails memory localNetworkDetails,
    Register.NetworkDetails memory remoteNetworkDetails,
    RebaseToken localToken,
    RebaseToken remoteToken
  ) public {
    // create the message to send tokens cross-chain
    vm.selectFork(localFork);
    vm.startPrank(user);
    Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
    tokenAmounts[0] = Client.EVMTokenAmount({
      token: address(localToken),
      amount: amountToBridge
    });
    Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
      receiver: abi.encode(user), // encode the address to bytes
      data: "", // no data needed for this example
      tokenAmounts: tokenAmounts, // needs to be of type EVMTokenAmount[] as one can send multiple tokens
      feeToken: localNetworkDetails.linkAddress, // token used to pay for the fee
      extraArgs: Client._argsToBytes(Client.EVMExtraArgsV2({gasLimit: 500_000, allowOutOfOrderExecution: false}))
    });
    // aprove the router to burn tokens on user behalf
    uint256 fee = IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message);
    IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, fee);
    vm.stopPrank();
    // give the user the fee amount of LINK
    ccipLocalSimulatorFork.requestLinkFromFaucet(user, fee);

    vm.startPrank(user);
    // approve the LINK fee
    IERC20(localNetworkDetails.linkAddress).approve(
      localNetworkDetails.routerAddress,
      IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message)
    ); // approve the fee
    // Approve the token being bridged
    IERC20(address(localToken)).approve(
      localNetworkDetails.routerAddress,
      amountToBridge
    );
    // log the values before bridging
    uint256 localBalanceBeforeBridge = IERC20(address(localToken)).balanceOf(user);
    console.log("Local balance before bridging:", localBalanceBeforeBridge);

    IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message); // send the message
    uint256 localBalanceAfterBridge = IERC20(address(localToken)).balanceOf(user);
    console.log("local balance after bridging:", localBalanceAfterBridge);
    assertEq(localBalanceAfterBridge, localBalanceBeforeBridge - amountToBridge);
    uint256 localUserInterestRate = localToken.getUserInterestRate(user);
    vm.stopPrank();

    vm.selectFork(remoteFork);
    // pretend it takes 15 minutes to bridge the tokens
    vm.warp(block.timestamp + 900);
    // get initial balance on arb-sepolia
    uint256 remoteBalanceBeforeBridging = IERC20(address(remoteToken)).balanceOf(user);
    console.log("remote balance before bridging:", remoteBalanceBeforeBridging);
    
    vm.selectFork(localFork);
    ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);
    uint256 remoteBalanceAfterBridging = remoteToken.balanceOf(user);
    assertEq(remoteBalanceAfterBridging, remoteBalanceBeforeBridging + amountToBridge);
    uint256 remoteUserInterestRate = remoteToken.getUserInterestRate(user);
    assertEq(remoteUserInterestRate, localUserInterestRate);
  }

  // writing a test for the bridgeToken function
  // this is not going to be a fuzz test so We won't pass any arguments
  function testBridgeTokens() public {
    // first select the fork we will be bridging from
    vm.selectFork(sepoliaFork);
    // then make a deposit to the vault
    vm.deal(user, SEND_VALUE);
    // deposit to the vault as the user
    vm.startPrank(user);
    // make the vault payable and cast to the vault contract so the deposit function can be called on it
    Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
    // check that the user balance and SEND_VALUE are equal
    uint256 startBalance = IERC20(address(sepoliaToken)).balanceOf(user);
    assertEq(startBalance, SEND_VALUE);
    vm.stopPrank();
    // now we bridge the tokens from sepolia to arb
    bridgeTokens(
      SEND_VALUE,
      sepoliaFork,
      arbSepoliaFork,
      sepoliaNetworkDetails,
      arbSepoliaNetworkDetails,
      sepoliaToken,
      arbSepoliaToken
    );
  }
}