/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */
import {
  Contract,
  ContractFactory,
  ContractTransactionResponse,
  Interface,
} from "ethers";
import type {
  Signer,
  BigNumberish,
  AddressLike,
  ContractDeployTransaction,
  ContractRunner,
} from "ethers";
import type { NonPayableOverrides } from "../common";
import type { ShareSample, ShareSampleInterface } from "../ShareSample";

const _abi = [
  {
    inputs: [
      {
        internalType: "address",
        name: "_withdrawAddress",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_subscriptionRate",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "_sharesSubject",
        type: "address",
      },
    ],
    stateMutability: "nonpayable",
    type: "constructor",
  },
  {
    inputs: [],
    name: "InsufficientSubscriptionPool",
    type: "error",
  },
  {
    inputs: [],
    name: "InvalidAlterPriceValue",
    type: "error",
  },
  {
    inputs: [],
    name: "InvalidAlterSubscriptionPoolValue",
    type: "error",
  },
  {
    inputs: [],
    name: "InvalidAssessmentFee",
    type: "error",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: false,
        internalType: "uint256",
        name: "tokenId",
        type: "uint256",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "feeCollected",
        type: "uint256",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "subscriptionPoolRemaining",
        type: "uint256",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "liquidationStartedAt",
        type: "uint256",
      },
    ],
    name: "FeeCollected",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: false,
        internalType: "address",
        name: "trader",
        type: "address",
      },
      {
        indexed: false,
        internalType: "address",
        name: "subject",
        type: "address",
      },
      {
        indexed: false,
        internalType: "bool",
        name: "isBuy",
        type: "bool",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "shareAmount",
        type: "uint256",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "ethAmount",
        type: "uint256",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "supply",
        type: "uint256",
      },
    ],
    name: "Trade",
    type: "event",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "buyShares",
    outputs: [],
    stateMutability: "payable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "tokenId",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "decreaseSubscriptionPool",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "getBuyPrice",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "getCurrentPrice",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "getMinimumSubPool",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "_supply",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "getPrice",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "pure",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "getSellPrice",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "getSubscriptionPoolRemaining",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "tokenId",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "increaseSubscriptionPool",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256[]",
        name: "tokenIds",
        type: "uint256[]",
      },
    ],
    name: "reapAndWithdrawFees",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256[]",
        name: "tokenIds",
        type: "uint256[]",
      },
    ],
    name: "reapSafForTokenIds",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "sellShares",
    outputs: [],
    stateMutability: "payable",
    type: "function",
  },
  {
    inputs: [],
    name: "withdrawAccumulatedFees",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
] as const;

const _bytecode =
  "0x60806040526103e860035561271060045561271060055534801561002257600080fd5b50604051610cec380380610cec83398101604081905261004191610097565b600191909155600a80546001600160a01b039384166001600160a01b031991821617909155600b80549390921692169190911790556100d3565b80516001600160a01b038116811461009257600080fd5b919050565b6000806000606084860312156100ac57600080fd5b6100b58461007b565b9250602084015191506100ca6040850161007b565b90509250925092565b610c0a806100e26000396000f3fe6080604052600436106100c25760003560e01c80634ba8ae811161007f578063ba730e5311610059578063ba730e53146101bd578063c4d676a1146100c7578063d1a93d18146101dd578063eb91d37e146101f057600080fd5b80634ba8ae811461016a5780635cf4ee911461017d5780639a8a63701461019d57600080fd5b806301814e14146100c757806308d4db14146100e857806309cd84931461011a57806312698ef31461012f57806322a295a81461014a5780632e185ec71461015e575b600080fd5b3480156100d357600080fd5b506100e66100e2366004610a80565b5050565b005b3480156100f457600080fd5b50610108610103366004610aa2565b610205565b60405190815260200160405180910390f35b34801561012657600080fd5b50610108610219565b34801561013b57600080fd5b506100e66100e2366004610abb565b34801561015657600080fd5b506000610108565b3480156100e657600080fd5b6100e6610178366004610aa2565b61024c565b34801561018957600080fd5b50610108610198366004610a80565b610431565b3480156101a957600080fd5b506100e66101b8366004610abb565b6100e2565b3480156101c957600080fd5b506101086101d8366004610aa2565b610552565b6100e66101eb366004610aa2565b610565565b3480156101fc57600080fd5b5061010861088e565b600061021360085483610431565b92915050565b33600081815260076020526040812054600854919283926102459290610240906001610431565b6108a2565b5092915050565b80600854116102a25760405162461bcd60e51b815260206004820152601a60248201527f43616e6e6f742073656c6c20746865206c61737420736861726500000000000060448201526064015b60405180910390fd5b60006102bb826008546102b59190610b46565b83610431565b336000908152600760205260409020549091508211156103135760405162461bcd60e51b8152602060048201526013602482015272496e73756666696369656e742073686172657360681b6044820152606401610299565b3360008181526007602052604081205490918291610334919061024061088e565b336000908152600760205260409020549193509150610354908590610b46565b33600090815260076020526040902055600854610372908590610b46565b6008553360009081526020819052604090208281554260019091015580600960008282546103a09190610b59565b9091555050600b546008547ff7dd8a134438de4c59401760e24ef5c6cc9c74583b2b022085697f3021e597689133916001600160a01b0390911690600090889088906103ed908390610b46565b604080516001600160a01b039788168152959096166020860152921515848601526060840191909152608083015260a082015290519081900360c00190a150505050565b600080831561048c576006610447600186610b46565b610452906002610b6c565b61045d906001610b59565b85610469600182610b46565b6104739190610b6c565b61047d9190610b6c565b6104879190610b83565b61048f565b60005b90506000841580156104a15750836001145b610516576006846104b3600188610b46565b6104bd9190610b59565b6104c8906002610b6c565b6104d3906001610b59565b6104dd8688610b59565b866104e960018a610b46565b6104f39190610b59565b6104fd9190610b6c565b6105079190610b6c565b6105119190610b83565b610519565b60005b905060006105278383610b46565b9050613e8061053e82670de0b6b3a7640000610b6c565b6105489190610b83565b9695505050505050565b6000610213826008546102b59190610b46565b600060085411806105805750600b546001600160a01b031633145b6105e55760405162461bcd60e51b815260206004820152603060248201527f4f6e6c79207468652073686172657327207375626a6563742063616e2062757960448201526f2074686520666972737420736861726560801b6064820152608401610299565b60006105f360085483610431565b905060006106176106128460085461060b9190610b59565b6001610431565b610917565b90508134116106615760405162461bcd60e51b8152602060048201526016602482015275496e75736666696369656e74206e667420707269636560501b6044820152606401610299565b600061066d8334610b46565b3360008181526007602052604081205492935091829161068f9161024061088e565b909250905060006106a08385610b59565b90508481116106e85760405162461bcd60e51b8152602060048201526014602482015273125b9cdd59999a58da595b9d081c185e5b595b9d60621b6044820152606401610299565b81600960008282546106fa9190610b59565b909155506107af905061070b61088e565b60408051606081018252428152602081019283526001805492820192835260028054918201815560005290517f405787fa12a823e0f2b7631cc41b3ba8828b3321ca811111fa75cd3aa3bb5ace60039092029182015591517f405787fa12a823e0f2b7631cc41b3ba8828b3321ca811111fa75cd3aa3bb5acf830155517f405787fa12a823e0f2b7631cc41b3ba8828b3321ca811111fa75cd3aa3bb5ad090910155565b336000908152600760205260409020546107ca908890610b59565b336000908152600760205260409020556008546107e8908890610b59565b600890815533600081815260208190526040902083815542600191820155600b5492547ff7dd8a134438de4c59401760e24ef5c6cc9c74583b2b022085697f3021e59768936001600160a01b031691908b908b90610847908390610b59565b604080516001600160a01b039788168152959096166020860152921515848601526060840191909152608083015260a082015290519081900360c00190a150505050505050565b600061089d6008546001610431565b905090565b6001600160a01b03831660009081526020818152604080832081518083019092528054808352600190910154928201839052839283916108e491879189610934565b825190915081106108fc5760009350915061090f9050565b8151610909908290610b46565b93509150505b935093915050565b60006127106003548361092a9190610b6c565b6102139190610b83565b6000808085815b600254811015610a0c5760006002828154811061095a5761095a610ba5565b90600052602060002090600302016040518060600160405290816000820154815260200160018201548152602001600282015481525050905082816000015111156109f95760006109b982602001518584600001518560400151610a3d565b6109c39089610b6c565b90506109cf8187610b59565b9550888611156109e757859650505050505050610a35565b815193506109f58186610b59565b9450505b5080610a0481610bbb565b91505061093b565b50610a1b888242600154610a3d565b610a259086610b6c565b610a2f9084610b59565b93505050505b949350505050565b6000610a4f6301e13380612710610b6c565b610a598585610b46565b610a638785610b6c565b610a6d9190610b6c565b610a779190610b83565b95945050505050565b60008060408385031215610a9357600080fd5b50508035926020909101359150565b600060208284031215610ab457600080fd5b5035919050565b60008060208385031215610ace57600080fd5b823567ffffffffffffffff80821115610ae657600080fd5b818501915085601f830112610afa57600080fd5b813581811115610b0957600080fd5b8660208260051b8501011115610b1e57600080fd5b60209290920196919550909350505050565b634e487b7160e01b600052601160045260246000fd5b8181038181111561021357610213610b30565b8082018082111561021357610213610b30565b808202811582820484141761021357610213610b30565b600082610ba057634e487b7160e01b600052601260045260246000fd5b500490565b634e487b7160e01b600052603260045260246000fd5b600060018201610bcd57610bcd610b30565b506001019056fea26469706673582212201ad1284b16a69caf0aad708071b3e1d3abdc17774c861638e342ed9b6288b78264736f6c63430008120033";

type ShareSampleConstructorParams =
  | [signer?: Signer]
  | ConstructorParameters<typeof ContractFactory>;

const isSuperArgs = (
  xs: ShareSampleConstructorParams
): xs is ConstructorParameters<typeof ContractFactory> => xs.length > 1;

export class ShareSample__factory extends ContractFactory {
  constructor(...args: ShareSampleConstructorParams) {
    if (isSuperArgs(args)) {
      super(...args);
    } else {
      super(_abi, _bytecode, args[0]);
    }
  }

  override getDeployTransaction(
    _withdrawAddress: AddressLike,
    _subscriptionRate: BigNumberish,
    _sharesSubject: AddressLike,
    overrides?: NonPayableOverrides & { from?: string }
  ): Promise<ContractDeployTransaction> {
    return super.getDeployTransaction(
      _withdrawAddress,
      _subscriptionRate,
      _sharesSubject,
      overrides || {}
    );
  }
  override deploy(
    _withdrawAddress: AddressLike,
    _subscriptionRate: BigNumberish,
    _sharesSubject: AddressLike,
    overrides?: NonPayableOverrides & { from?: string }
  ) {
    return super.deploy(
      _withdrawAddress,
      _subscriptionRate,
      _sharesSubject,
      overrides || {}
    ) as Promise<
      ShareSample & {
        deploymentTransaction(): ContractTransactionResponse;
      }
    >;
  }
  override connect(runner: ContractRunner | null): ShareSample__factory {
    return super.connect(runner) as ShareSample__factory;
  }

  static readonly bytecode = _bytecode;
  static readonly abi = _abi;
  static createInterface(): ShareSampleInterface {
    return new Interface(_abi) as ShareSampleInterface;
  }
  static connect(address: string, runner?: ContractRunner | null): ShareSample {
    return new Contract(address, _abi, runner) as unknown as ShareSample;
  }
}
