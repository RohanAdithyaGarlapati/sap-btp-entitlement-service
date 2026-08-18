using EntitlementService as service from '../srv/service';

///////////////////////////////////////////////////////////////////////
// Entitlements: list report + object page
///////////////////////////////////////////////////////////////////////
annotate service.Entitlements with @(
  UI: {
    HeaderInfo: {
      TypeName      : 'Entitlement',
      TypeNamePlural: 'Entitlements',
      Title         : { Value: subaccount },
      Description   : { Value: plan }
    },

    SelectionFields: [ subaccount, plan, status, product_ID ],

    LineItem: [
      { Value: subaccount,     Label: 'Subaccount' },
      { Value: product.name,   Label: 'Product' },
      { Value: plan,           Label: 'Plan' },
      { Value: quota,          Label: 'Quota' },
      { Value: unit,           Label: 'Unit' },
      { Value: remainingQuota, Label: 'Remaining', Criticality: statusCriticality },
      { Value: status,         Label: 'Status',    Criticality: statusCriticality },
      { Value: validFrom,      Label: 'Valid From' },
      { Value: validTo,        Label: 'Valid To' },
      { $Type : 'UI.DataFieldForAction',
        Action: 'EntitlementService.recordConsumption',
        Label : 'Record Consumption' }
    ],

    Facets: [
      { $Type: 'UI.ReferenceFacet', ID: 'General',
        Label: 'General Information', Target: '@UI.FieldGroup#General' },
      { $Type: 'UI.ReferenceFacet', ID: 'Validity',
        Label: 'Validity & Quota', Target: '@UI.FieldGroup#Validity' },
      { $Type: 'UI.ReferenceFacet', ID: 'Consumptions',
        Label: 'Consumption Records', Target: 'consumptions/@UI.LineItem' }
    ],

    FieldGroup #General: {
      Data: [
        { Value: subaccount,   Label: 'Subaccount' },
        { Value: product_ID,   Label: 'Product' },
        { Value: plan,         Label: 'Plan' },
        { Value: status,       Label: 'Status', Criticality: statusCriticality }
      ]
    },

    FieldGroup #Validity: {
      Data: [
        { Value: quota,          Label: 'Quota' },
        { Value: unit,           Label: 'Unit' },
        { Value: consumedQuota,  Label: 'Consumed' },
        { Value: remainingQuota, Label: 'Remaining' },
        { Value: validFrom,      Label: 'Valid From' },
        { Value: validTo,        Label: 'Valid To' },
        { Value: autoRenew,      Label: 'Auto Renew' }
      ]
    }
  }
) {
  subaccount @title: 'Subaccount';
  plan       @title: 'Plan';
  quota      @title: 'Quota';
  unit       @title: 'Unit';
  status     @title: 'Status';
};

// data point that colours the remaining quota by criticality
annotate service.Entitlements with @(
  UI.DataPoint #remaining: {
    Value      : remainingQuota,
    Title      : 'Remaining Quota',
    Criticality: statusCriticality
  }
);

///////////////////////////////////////////////////////////////////////
// Consumption records: table shown on the object page
///////////////////////////////////////////////////////////////////////
annotate service.Consumptions with @(
  UI.LineItem: [
    { Value: usageDate, Label: 'Usage Date' },
    { Value: amount,    Label: 'Amount' },
    { Value: unit,      Label: 'Unit' },
    { Value: region,    Label: 'Region' },
    { Value: note,      Label: 'Note' }
  ]
);

///////////////////////////////////////////////////////////////////////
// Products value help
///////////////////////////////////////////////////////////////////////
annotate service.Entitlements with {
  product @(
    Common.Text           : product.name,
    Common.TextArrangement: #TextOnly,
    Common.ValueList      : {
      CollectionPath: 'Products',
      Parameters    : [
        { $Type: 'Common.ValueListParameterInOut',
          LocalDataProperty: product_ID, ValueListProperty: 'ID' },
        { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'code' },
        { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'name' },
        { $Type: 'Common.ValueListParameterDisplayOnly', ValueListProperty: 'unit' }
      ]
    }
  );
};
