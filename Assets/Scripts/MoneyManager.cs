using UnityEngine;
using System;

/// <summary>
/// Tracks the player's money. Auto-finds or creates itself as a singleton.
/// </summary>
public class MoneyManager : MonoBehaviour
{
    public static MoneyManager Instance { get; private set; }

    [Header("Starting Balance")]
    public int startingMoney = 500;

    /// <summary>Current money balance.</summary>
    public int CurrentMoney { get; private set; }

    /// <summary>Fires when money changes. Args: newAmount, delta.</summary>
    public event Action<int, int> OnMoneyChanged;

    void Awake()
    {
        if (Instance != null && Instance != this)
        {
            Destroy(gameObject);
            return;
        }
        Instance = this;
        CurrentMoney = startingMoney;
    }

    /// <summary>Add money (positive = earn, negative = spend). Returns true if transaction succeeded.</summary>
    public bool ChangeMoney(int amount)
    {
        if (CurrentMoney + amount < 0)
            return false;

        CurrentMoney += amount;
        OnMoneyChanged?.Invoke(CurrentMoney, amount);
        return true;
    }

    /// <summary>Check if the player can afford a cost.</summary>
    public bool CanAfford(int cost) => CurrentMoney >= cost;
}
