require('babel-register');

const RoT = artifacts.require("RoT");
const ESOP = artifacts.require("ESOP");
const CALCULATOR = artifacts.require("OptionsCalculator");
const EMPLIST = artifacts.require("EmployeesList");
// test types
const UPD_ESOP = artifacts.require("UpdatedESOP");
const UPDATER = artifacts.require("TestCodeUpdater");

const currdate = (new Date()) / 1;
const weeks = 7 * 24 * 60 * 60;
const extraOptionsAmount = 8172;


contract('CodeUpdateable', function (accounts) {
  function addemployees(esop, company) {
    let startdate = currdate;
    accounts.filter(a => a !== company).map(async function(e) {
        // function offerOptionsToEmployee(address e, uint32 vestingStarts, uint32 timeToSign, uint32 extraOptions, bool poolCleanup)
        let tx = await esop.offerOptionsToEmployee(e, startdate - 1 * weeks, startdate + 4 * weeks, extraOptionsAmount, false);
        if (tx.logs.some(e => e.event === 'ESOPOffered')) {
            console.log(`employee ${e} added with ${tx.logs[0].args['poolOptions']} poolOptions`);
        } else {
            console.log(`offerOptionsToEmployee returned rc: ${tx.logs[0].args['rc']}`);
            throw `offerOptionsToEmployee returned rc: ${tx.logs[0].args['rc']}`;
        }
    });
  }
  it('update to identical ESOP', async () => {
      let rot = await RoT.deployed();
      let esop = ESOP.at(await rot.ESOPAddress());
      let companyAddress = await esop.companyAddress();
      addemployees(esop, companyAddress);
      // updated options calculator
      let oldcal = CALCULATOR.at(await esop.optionsCalculator());
      let newcal = await CALCULATOR.new(await oldcal.cliffPeriod(), await oldcal.vestingPeriod(), await oldcal.FP_SCALE() - await oldcal.maxFadeoutPromille(),
        await oldcal.bonusOptionsPromille(), await oldcal.newEmployeePoolPromille(), await oldcal.optionsPerShare());
      // empty employees list
      let newemplist = await EMPLIST.new();
      let oldemplist = EMPLIST.at(await esop.employees());
      // create updater
      console.log('creating updater');
      let updater = await UPDATER.new(oldemplist.address, newemplist.address);
      // let updater modify new employees list
      await newemplist.transferOwnership(updater.address);
      // updated esop instance, this also copies state from old one!
      console.log('creating new esop instance');
      let newLegalWHash = new Buffer("QmRsjnNkEpnDdmYB7wMR7FSy1eGZ12pDuhST3iNLJTzAXF", 'ascii');
      // give a lot of gas
      let newesop = await UPD_ESOP.new(companyAddress, rot.address, {gas: 15000000});
      console.log('migrating state to new esop');
      await newesop.migrateState(esop.address, newcal.address, newemplist.address, web3.toBigNumber('0x' + newLegalWHash.toString('hex')));
      // put old esop in maintenance mode
      await esop.beginCodeUpdate();
      // move all employees
      let idx = 0, processed = 0, maxcount = 2;
      let tot_size = await oldemplist.size();
      console.log(`migrating ${tot_size} employees`);
      do {
        // process 2 employees at a time
        let emp_m_tx = await updater.migrateEmployeesList(idx, maxcount);
        if (emp_m_tx.logs.some(e => e.event == 'RV')) {
          // error code returned
          processed = Number(emp_m_tx.logs[0].args['rc']);
        }
        idx += processed;
        // console.log(`processed ${processed} employees idx is ${idx}`);
      } while(processed == maxcount);
      // updater gives back ownership to newesop
      await updater.transferEmployeesListOwnership(newesop.address);
      // cancel code update on new esop to put it back in operational state
      await newesop.cancelCodeUpdate();
      let newesop_pooloptions = Number(await newesop.totalPoolOptions());
      let newesop_extraoptions = Number(await newesop.totalExtraOptions());
      let newesop_remainingpool = Number(await newesop.remainingPoolOptions());
      assert.equal(Number(tot_size), Number(await newemplist.size()), "sizes of employees lists must be equal");
      assert.equal(Number(await esop.totalPoolOptions()), newesop_pooloptions, 'totalPoolOptions');
      assert.equal(Number(await esop.totalExtraOptions()), newesop_extraoptions, 'totalExtraOptions');
      assert.equal(Number(await esop.remainingPoolOptions()), newesop_remainingpool, 'remainingPoolOptions');
      // sign to esop with employee no 1
      let sign_tx = await newesop.employeeSignsToESOP({from: accounts[1]});
      assert.equal(sign_tx.logs[0].args['employee'], accounts[1], 'employee signs to ESOP');
      // CEO removes last employee
      let employee_l = await newemplist.getSerializedEmployee(accounts[accounts.length-1]);
      // console.log(employee_4);
      let rem_tx = await newesop.terminateEmployee(accounts[accounts.length-1], currdate, 0);
      // check pool management
      assert.equal(Number(await newesop.totalExtraOptions()), newesop_extraoptions - extraOptionsAmount, 'totalExtraOptions - terminated');
      // last employee was terminated so all options were returned to pool
      assert.equal(Number(await newesop.remainingPoolOptions()), newesop_remainingpool + Number(employee_l[4]), 'remainingPoolOptions + terminated');
      // change in RoT
      let rot_change_tx = await rot.setESOP(newesop.address, companyAddress);
      let ev_set = rot_change_tx.logs[0];
      assert.equal(ev_set.args['ESOPAddress'], newesop.address, 'ESOPAddress');
      assert.equal(ev_set.args['companyAddress'], companyAddress, 'companyAddress');
      // this will kill old ESOP
      await esop.completeCodeUpdate();
      let nocode = web3.eth.getCode(esop.address);
      // console.log(nocode);
      assert.equal('0x0', nocode, 'old esop must die');
      await updater.selfdestruct();
      nocode = web3.eth.getCode(updater.address);
      assert.equal('0x0', nocode, 'updater must die');

  });
});
