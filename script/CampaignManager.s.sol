// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/CampaignManager.sol";
import "../src/ERC20CampaignTemplate.sol";

import {Script, console2} from "forge-std/Script.sol";
import "forge-std/console2.sol"; 
import "forge-std/StdCheats.sol";
import "forge-std/Vm.sol";
import "forge-std/Test.sol";

contract DeployCampaignFunding is Script {
    function setUp() public {}

    function run() public {
        uint256 privatekey =  vm.envUint("PRIVATE_KEY");
       address account = vm.addr(privatekey);
       console.log(account);

       
        vm.startBroadcast(privatekey);
        CampaignManager campaignManager = new CampaignManager();
        vm.stopBroadcast();
    }
}